#!/usr/bin/env python3
"""gdoc — рендерит офисные документы в PDF и открывает их в zathura.

Конвертер выбирается по расширению (см. FORMATS): pandoc для OOXML/ODF и
markdown, wvHtml для старого .doc, ssconvert для таблиц, свой обход XML для
.pptx. Все они дают HTML, его печатает в PDF headless-chromium.

Разметку от конвертеров нельзя считать доверенной: pandoc пропускает сырой
HTML из markdown и epub насквозь, так что документ может принести <script>,
<iframe file://> и onerror=. Поэтому чужой HTML проходит через sanitize(), а
chromium печатает с отключённой сетью. Свой скрипт (подгонка формул)
добавляется уже после очистки.

Готовое складывается в кэш и переиспользуется, пока не изменился ни файл, ни
сам рендер. Публикация атомарная — параллельные запуски не мешают друг другу
и не оставляют недособранных записей.
"""

from __future__ import annotations

import argparse
import csv
import errno
import functools
import hashlib
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from typing import Callable, Iterable, NamedTuple
from xml.etree import ElementTree as ET

NS = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}

# Ячейка CSV может быть длиннее дефолтных 128 КБ — иначе csv.reader бросает
# Error и лист не открывается вовсе.
csv.field_size_limit(16 * 1024 * 1024)

# Сколько собранных документов держим в кэше.
CACHE_KEEP = 40
# Выше этого лист обрезается: PDF на сто тысяч строк бесполезен и собирается
# минутами.
MAX_ROWS = 5000
# Конвертеры иногда зависают на битом вводе. Из .desktop такой процесс уходит
# в фон навсегда, поэтому у каждого запуска есть потолок.
RUN_TIMEOUT = 300
PRINT_TIMEOUT = 180
# Глубже этого разметку уже никто не писал осмысленно, а очистка на
# вложенности в десятки тысяч тегов съедает секунды CPU.
MAX_DEPTH = 200
# Дольше этого недособранный каталог живым процессом держаться не может:
# потолок жизни запуска — RUN_TIMEOUT плюс PRINT_TIMEOUT.
STAGING_MAX_AGE = RUN_TIMEOUT + PRINT_TIMEOUT + 60
# Запись моложе этого кто-то прямо сейчас читает или печатает: build
# обновляет время доступа перед самой печатью.
CACHE_MIN_AGE = 120
# Потолок на распаковку вложений презентации, чтобы zip-бомба не легла
# в кэш целиком.
MAX_MEDIA_BYTES = 256 * 1024 * 1024
# Имя тега берётся из чужого документа и уезжает в вывод — пропускаем
# только то, что точно является именем.
TAG_NAME = re.compile(r"[a-zA-Z][a-zA-Z0-9:._-]*")
# Растровые data-картинки безопасны, в отличие от svg+xml, который
# является документом и умеет нести скрипты.
DATA_IMAGE = re.compile(r"data:image/(png|jpe?g|gif|webp|bmp|avif|tiff);")
# Цветовые функции CSS: аргументы у них только числовые, так что вырезать
# их из проверки значения безопасно.
COLOR_FN = re.compile(r"(?:rgba?|hsla?)\([0-9,.%/\s+-]*\)", re.I)


def tool(env_var: str, name: str) -> str:
    """Путь до утилиты: из окружения (его задаёт nix-обёртка) либо из PATH."""
    return os.environ.get(env_var) or shutil.which(name) or name


PANDOC = tool("GDOC_PANDOC", "pandoc")
WVHTML = tool("GDOC_WVHTML", "wvHtml")
SSCONVERT = tool("GDOC_SSCONVERT", "ssconvert")
CATPPT = tool("GDOC_CATPPT", "catppt")
ANTIWORD = tool("GDOC_ANTIWORD", "antiword")
CHROMIUM = tool("GDOC_CHROMIUM", "chromium")


class RenderError(Exception):
    """Ошибка, которую можно показать пользователю одной строкой.

    В `raw` лежит полный вывод программы: сообщение для человека урезано до
    пары строк, а разбирать причину иногда нужно по всему тексту.
    """

    def __init__(self, message: str, raw: str = "") -> None:
        super().__init__(message)
        self.raw = raw


# --------------------------------------------------------------------------
# очистка чужого HTML

class _Sanitizer(HTMLParser):
    """Выбрасывает из разметки всё активное, оставляя оформление.

    Денилист, а не аллоулист: конвертеры отдают произвольные теги оформления
    и весь MathML, перечислить их заранее нельзя. Опасного же — конечный
    список, и он ниже.
    """

    # Тег вместе с содержимым. Только те, у кого закрывающий тег бывает:
    # для остальных подавление некому снять, и остаток документа пропал бы
    # целиком — молча и без следа.
    DROP_TREE = frozenset({
        "script", "style", "noscript", "template", "iframe", "frameset",
        "object", "applet", "form", "title", "portal",
    })
    # Одиночные опасные теги: содержимого у них нет, подавлять нечего.
    # SMIL сюда же — он подставляет адрес в href уже после очистки, а лежит
    # тот в values/to/from, куда фильтр ссылок не смотрит.
    DROP_SELF = frozenset({
        "embed", "frame", "animate", "animatetransform", "animatemotion",
        "set",
    })
    # Сам тег выбрасываем, детей оставляем.
    DROP_TAG = frozenset({
        "html", "head", "body", "base", "link", "meta", "input", "button",
        "textarea", "select", "option",
    })
    VOID = frozenset({
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr",
    })
    URL_ATTRS = frozenset({
        "src", "href", "poster", "data", "action", "background",
        "formaction", "xlink:href", "longdesc", "cite", "profile", "manifest",
    })
    # srcset — список ссылок со своим синтаксисом; разбирать его ради
    # конвертеров, которые его не выдают, смысла нет.
    DROP_ATTRS = frozenset({"srcset", "imagesrcset", "ping", "target"})

    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.out: list[str] = []
        self.open_tags: list[str] = []
        # Счётчик открытых тегов по имени: проверка вхождения по списку
        # квадратична, и на документе с глубокой вложенностью очистка
        # занимала секунды CPU без всякого таймаута над ней.
        self.open_count: Counter[str] = Counter()
        self.suppress = 0
        self.dropped: Counter[str] = Counter()

    def _dropped(self, what: str) -> None:
        self.dropped[what] += 1
        return None

    # -- атрибуты -------------------------------------------------------

    def _safe_url(self, value: str) -> str | None:
        """Пропускаем только то, что лежит внутри каталога сборки.

        Не только «не ходит наружу»: страница живёт по file://, поэтому
        `/etc/hostname` и `../../x` тоже читаются и втягиваются в PDF.
        Разрешён лишь относительный путь без выхода вверх — такие ссылки
        и выдают конвертеры на вытащенные ими картинки.
        """
        v = value.strip()
        if not v:
            return None
        low = v.lower()
        if DATA_IMAGE.match(low):
            return v
        if low.startswith("data:"):  # в т.ч. svg+xml, а он умеет скрипты
            return self._dropped("ссылка наружу")
        if v.startswith("#"):  # якорь внутри страницы
            return v
        if low.startswith("//") or v.startswith(("/", "\\")):
            return self._dropped("ссылка наружу")
        if ":" in v.split("/", 1)[0]:  # http:, file:, javascript:, data:<не картинка>
            return self._dropped("ссылка наружу")
        if any(part == ".." for part in re.split(r"[/\\]", v)):
            return self._dropped("ссылка наружу")
        return v

    # Свойства, которыми конвертеры оформляют текст. Всё остальное режем:
    # денилист по подстрокам обходится эскейпом вида u\72l(...), который CSS
    # понимает, а `"url(" in value` — нет.
    STYLE_PROPS = frozenset({
        "color", "background-color", "background", "font", "font-size",
        "font-weight", "font-style", "font-family", "font-variant",
        "text-align", "text-decoration", "text-indent", "text-transform",
        "vertical-align", "line-height", "letter-spacing", "white-space",
        "margin", "margin-top", "margin-bottom", "margin-left", "margin-right",
        "padding", "padding-top", "padding-bottom", "padding-left",
        "padding-right", "border", "border-top", "border-bottom",
        "border-left", "border-right", "border-color", "border-style",
        "border-width", "border-collapse", "width", "height", "max-width",
        "min-width", "display", "float", "clear", "list-style", "list-style-type",
        # Печать — единственный режим вывода, разрывы страниц тут по делу.
        "page-break-before", "page-break-after", "page-break-inside",
        "break-before", "break-after", "break-inside",
    })

    def _safe_style(self, value: str) -> str | None:
        kept = []
        lost = 0
        for chunk in value.split(";"):
            prop, sep, val = chunk.partition(":")
            if not sep:
                continue
            prop = prop.strip().lower()
            val = val.strip()
            if not prop or not val:
                continue
            # Цветовые функции — основная форма записи цвета у офисных
            # конвертеров, поэтому их вырезаем из проверки, а не запрещаем.
            # Всё, что осталось со скобкой или эскейпом, отбрасываем: там
            # прячется url() в том числе в виде u\72l(...).
            if prop not in self.STYLE_PROPS or any(
                    c in COLOR_FN.sub("", val) for c in "(\\@{}"):
                lost += 1
                continue
            kept.append(f"{prop}: {val}")
        if lost:
            self.dropped["оформление"] += lost
        return "; ".join(kept) or None

    def _attrs(self, attrs: Iterable[tuple[str, str | None]]) -> str:
        parts = []
        for name, value in attrs:
            name = name.lower()
            if name.startswith("on") or name in self.DROP_ATTRS:
                continue
            if value is None:
                parts.append(f" {html.escape(name, quote=True)}")
                continue
            if name in self.URL_ATTRS:
                checked = self._safe_url(value)
            elif name == "style":
                checked = self._safe_style(value)
            else:
                checked = value
            if checked is None:
                continue
            parts.append(f' {html.escape(name, quote=True)}="{html.escape(checked, quote=True)}"')
        return "".join(parts)

    # -- обход ----------------------------------------------------------

    def _skip(self, tag: str) -> bool:
        """Тег, который не должен попасть в вывод как разметка."""
        if tag in self.DROP_TAG:
            return True
        if not TAG_NAME.fullmatch(tag):
            return True
        if len(self.open_tags) >= MAX_DEPTH:
            # Текст внутри останется, а структура — нет, так что ячейки и
            # абзацы за границей сольются. Сказать об этом обязательно.
            self.dropped["предел вложенности"] += 1
            return True
        return False

    def _count_lost(self, tag: str, attrs) -> None:
        """Учесть выброшенный элемент, если он тянул что-то извне."""
        if any(name.lower() in self.URL_ATTRS and value
               for name, value in attrs):
            self.dropped["внешняя вставка"] += 1

    def handle_starttag(self, tag: str, attrs) -> None:
        if self.suppress:
            if tag in self.DROP_TREE:
                self.suppress += 1
            return
        if tag in self.DROP_TREE:
            self._count_lost(tag, attrs)
            self.suppress = 1
            return
        if tag in self.DROP_SELF:
            self._count_lost(tag, attrs)
            return
        if self._skip(tag):
            return
        self.out.append(f"<{tag}{self._attrs(attrs)}>")
        if tag not in self.VOID:
            self.open_tags.append(tag)
            self.open_count[tag] += 1

    def handle_startendtag(self, tag: str, attrs) -> None:
        if self.suppress or tag in self.DROP_TREE:
            return
        if tag in self.DROP_SELF:
            self._count_lost(tag, attrs)
            return
        if self._skip(tag):
            return
        if tag in self.VOID:
            self.out.append(f"<{tag}{self._attrs(attrs)}>")
            return
        # В HTML косая черта перед `>` игнорируется, так что <section/> из
        # XHTML-подобного вывода открыл бы элемент и проглотил весь остаток
        # документа. Закрываем сразу — намерение было именно такое.
        self.out.append(f"<{tag}{self._attrs(attrs)}></{tag}>")

    def handle_endtag(self, tag: str) -> None:
        if self.suppress:
            if tag in self.DROP_TREE:
                self.suppress -= 1
            return
        if tag in self.DROP_TAG or tag in self.DROP_SELF or tag in self.VOID:
            return
        if not self.open_count[tag]:
            return  # закрытие без открытия — выбрасываем
        # Закрываем всё, что осталось незакрытым внутри: иначе чужая
        # несбалансированная разметка растащит вёрстку всей страницы.
        while self.open_tags:
            current = self.open_tags.pop()
            self.open_count[current] -= 1
            self.out.append(f"</{current}>")
            if current == tag:
                break

    def handle_data(self, data: str) -> None:
        if not self.suppress:
            self.out.append(html.escape(data, quote=False))

    def handle_entityref(self, name: str) -> None:
        if not self.suppress:
            self.out.append(f"&{name};")

    def handle_charref(self, name: str) -> None:
        if not self.suppress:
            self.out.append(f"&#{name};")

    def result(self) -> str:
        while self.open_tags:
            self.out.append(f"</{self.open_tags.pop()}>")
        return "".join(self.out)


def sanitize(markup: str) -> tuple[str, Counter[str]]:
    """Очистить разметку конвертера. Возвращает ещё и список потерь.

    О потерянном надо сказать: документ со ссылочными иллюстрациями иначе
    открывается с пустыми местами и без единого намёка, что что-то вырезано.
    """
    parser = _Sanitizer()
    parser.feed(markup)
    parser.close()
    return parser.result(), parser.dropped


# Как объяснять потерю каждого вида — по-русски, а не именем счётчика.
LOSS_WORDING = {
    "ссылка наружу": "ссылок на внешние ресурсы: {n} (документ тянул их из "
                     "сети или из файловой системы, на их месте пусто)",
    "внешняя вставка": "внешних вставок: {n} (видео, фреймы и подобное)",
    "оформление": "правил оформления: {n} (они умели подгружать что-то "
                  "извне)",
    "предел вложенности": "уровней вложенности: {n} — дальше разметка "
                          "слишком глубокая, текст там мог слипнуться",
}


def sanitized_body(markup: str) -> str:
    """Очищенная разметка вместе с плашкой о вырезанном, если оно было."""
    body, dropped = sanitize(markup)
    if not dropped:
        return body
    parts = [
        LOSS_WORDING.get(kind, kind + ": {n}").format(n=count)
        for kind, count in dropped.most_common()
    ]
    return note("Вырезано " + "; ".join(parts) + ".") + body


# --------------------------------------------------------------------------
# страница

PAGE_CSS = """
*, *::before, *::after { box-sizing: border-box; }
body {
  margin: 0;
  padding: 28px 16px 64px;
  background: #e9eaec;
  color: #16181d;
  font: 16px/1.6 "Liberation Serif", Georgia, serif;
}
.sheet {
  max-width: 50rem;
  margin: 0 auto;
  padding: 3.5rem 4rem;
  background: #fff;
  border-radius: 3px;
  box-shadow: 0 1px 3px rgba(0,0,0,.18), 0 8px 24px rgba(0,0,0,.08);
  overflow-wrap: break-word;
}
.sheet--wide { max-width: min(96rem, 100%); padding: 2rem; overflow-x: auto; }
.topbar {
  max-width: 50rem;
  margin: 0 auto .75rem;
  display: flex;
  gap: .6rem;
  align-items: baseline;
  font: 13px/1.4 system-ui, sans-serif;
  color: #5d616b;
}
.topbar--wide { max-width: min(96rem, 100%); }
.topbar b { color: #16181d; font-weight: 600; }
.topbar .kind {
  padding: .1rem .45rem;
  border-radius: 3px;
  background: #d5d7db;
  font-size: 11px;
  letter-spacing: .04em;
  text-transform: uppercase;
}
h1, h2, h3, h4, h5, h6 { font-family: "Liberation Sans", system-ui, sans-serif; line-height: 1.25; }
h1 { font-size: 1.9rem; }
h2 { font-size: 1.5rem; }
h3 { font-size: 1.22rem; }
img { max-width: 100%; height: auto; }
table { border-collapse: collapse; margin: 1rem 0; font-size: .93em; }
td, th { border: 1px solid #c8cbd1; padding: .28rem .5rem; vertical-align: top; }
th { background: #f1f2f4; }
td.n { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
caption {
  caption-side: top;
  padding: 1.2rem 0 .35rem;
  font: 600 12px/1.4 system-ui, sans-serif;
  letter-spacing: .05em;
  text-transform: uppercase;
  color: #5d616b;
  text-align: left;
}
pre { overflow-x: auto; }
math { font-size: 1.05em; }
.mathfit { display: block; overflow: hidden; }
.note {
  margin: 1.2rem 0;
  padding: .7rem 1rem;
  border-left: 3px solid #d0a215;
  background: #fdf6e0;
  font: 13px/1.5 system-ui, sans-serif;
  color: #5b4a10;
}
.slide { margin: 0 0 2rem; padding: 1.5rem 1.8rem; border: 1px solid #d8dade; border-radius: 4px; }
.slide > .num {
  display: block;
  margin-bottom: .8rem;
  font: 11px/1 system-ui, sans-serif;
  letter-spacing: .08em;
  text-transform: uppercase;
  color: #82868f;
}
.slide h2 { margin-top: 0; }
.lvl1 { margin-left: 1.5rem; }
.lvl2 { margin-left: 3rem; }
.lvl3 { margin-left: 4.5rem; }
.gallery { display: flex; flex-wrap: wrap; gap: .8rem; }
.gallery img {
  max-width: 20rem;
  max-height: 18rem;
  object-fit: contain;
  border: 1px solid #d8dade;
}
@media (prefers-color-scheme: dark) {
  /* Лист остаётся белым: конвертеры пишут в разметку свои background-color,
     и на сером фоне абзацы начинают полосить. Цвет текста внутри листа
     поэтому тоже надо вернуть тёмный — он не наследуется от body. */
  body { background: #17181b; color: #e6e7ea; }
  .sheet { color: #16181d; }
  .topbar { color: #9a9ea8; }
  .topbar b { color: #e6e7ea; }
  .topbar .kind { background: #2c2e34; }
}
/* Печать в PDF: поля рисует @page, экранная «бумага» тут только мешает. */
@media print {
  body { background: #fff; padding: 0; }
  .topbar { display: none; }
  .sheet {
    max-width: none;
    margin: 0;
    padding: 0;
    border-radius: 0;
    box-shadow: none;
    overflow: visible;
  }
  img, tr, .note, .gallery img { break-inside: avoid; }
  table { font-size: .85em; }
  .slide {
    border: 0;
    padding: 0;
    margin: 0;
    break-inside: avoid;
    break-after: page;
  }
  .slide:last-child { break-after: auto; }
  .slide > .num { color: #82868f; }
}
"""


# MathML не переносится по строкам, и длинные выражения уезжают за правое
# поле страницы. Ужимаем такие формулы до ширины колонки: пересчёт висит и
# на beforeprint, потому что при печати ширина страницы другая, чем на экране.
PAGE_JS = """
function fitMath() {
  document.querySelectorAll('math').forEach(function (m) {
    var holder = m.parentElement &&
      m.parentElement.classList.contains('mathfit') ? m.parentElement : null;
    m.style.transform = '';
    m.style.display = '';
    m.style.width = '';
    if (holder) holder.style.height = '';

    var host = holder ? holder.parentElement : m.parentElement;
    var avail = host ? host.clientWidth : 0;
    // Блочный <math> отдаёт в rect ширину контейнера, а не содержимого,
    // поэтому настоящую ширину спрашиваем через max-content.
    m.style.display = 'inline-block';
    m.style.width = 'max-content';
    var r = m.getBoundingClientRect();

    if (!avail || !r.width || r.width <= avail) {
      m.style.display = '';
      m.style.width = '';
      return;
    }
    var s = avail / r.width;
    if (!holder) {
      holder = document.createElement('span');
      holder.className = 'mathfit';
      m.parentNode.insertBefore(holder, m);
      holder.appendChild(m);
    }
    holder.style.height = (r.height * s) + 'px';
    m.style.transformOrigin = 'left top';
    m.style.transform = 'scale(' + s + ')';
  });
}
addEventListener('load', fitMath);
addEventListener('beforeprint', fitMath);
"""


def page(title: str, kind: str, body: str, wide: bool = False) -> str:
    """Собрать страницу вокруг уже очищенной разметки документа."""
    topbar_mod = " topbar--wide" if wide else ""
    sheet_mod = " sheet--wide" if wide else ""
    # Широкие таблицы иначе обрезаются по правому краю страницы.
    orient = "A4 landscape" if wide else "A4"
    return (
        '<!DOCTYPE html>\n<html lang="ru"><head><meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"<title>{html.escape(title)}</title>\n"
        f"<style>{PAGE_CSS}@page {{ size: {orient}; margin: 15mm 14mm; }}</style>"
        "</head>\n"
        f'<body>\n<div class="topbar{topbar_mod}"><b>{html.escape(title)}</b>'
        f'<span class="kind">{html.escape(kind)}</span></div>\n'
        f'<main class="sheet{sheet_mod}">\n{body}\n</main>\n'
        f"<script>{PAGE_JS}</script>\n</body></html>\n"
    )


def note(text: str) -> str:
    return f'<p class="note">{html.escape(text)}</p>\n'


def run(cmd: list[str], timeout: int = RUN_TIMEOUT, **kw) -> bytes:
    """Запустить конвертер, превратив падение в читаемую RenderError."""
    kw.setdefault("stdout", subprocess.PIPE)
    kw.setdefault("stderr", subprocess.PIPE)
    name = Path(cmd[0]).name
    try:
        proc = subprocess.run(cmd, timeout=timeout, **kw)
    except FileNotFoundError:
        raise RenderError(f"не найдена программа {name}") from None
    except subprocess.TimeoutExpired:
        raise RenderError(f"{name} не уложился в {timeout} с") from None
    if proc.returncode != 0:
        raw = (proc.stderr or b"").decode("utf-8", "replace")
        raise RenderError(f"{name}: {_why(proc.stderr, proc.returncode)}", raw)
    return proc.stdout or b""


def _why(stderr: bytes | None, code: int) -> str:
    """Последние осмысленные строки вывода — без шума окружения."""
    text = (stderr or b"").decode("utf-8", "replace")
    lines = [
        line.strip() for line in text.splitlines()
        if line.strip() and "dconf" not in line and "dbus" not in line
    ]
    # У pandoc последняя строка — служебная ссылка на исходники GHC,
    # полезное лежит выше.
    lines = [line for line in lines if "called at libraries/" not in line]
    return "; ".join(lines[-2:]) if lines else f"код {code}"


# --------------------------------------------------------------------------
# картинки из бинарных форматов

# Ниже этого JPEG почти наверняка не картинка документа, а превью-иконка или
# случайное совпадение сигнатуры.
MIN_JPEG = 1024


def _png_end(data: bytes, start: int) -> int | None:
    """Конец PNG, если от start начинается корректная цепочка чанков."""
    n = len(data)
    i = start + 8
    while i + 8 <= n:
        length = int.from_bytes(data[i:i + 4], "big")
        kind = data[i + 4:i + 8]
        nxt = i + 8 + length + 4
        if length < 0 or nxt > n:
            return None
        if kind == b"IEND":
            return nxt
        i = nxt
    return None


def _jpeg_end(data: bytes, start: int) -> int | None:
    """Конец JPEG, если от start начинается корректная цепочка сегментов."""
    n = len(data)
    # Сигнатура — это FF D8 FF, где третий байт уже начало первого сегмента.
    # Сразу за ним обязан идти код маркера; если там мусор, значит совпали
    # случайные три байта, а не начало картинки.
    if start + 4 > n or not 0xC0 <= data[start + 3] <= 0xFE:
        return None
    i = start + 2
    # Двух байт достаточно: маркер конца длину за собой не тащит, и картинка
    # вполне может заканчиваться ровно на границе данных.
    while i + 2 <= n:
        if data[i] != 0xFF:
            return None
        marker = data[i + 1]
        if marker == 0xD9:
            return i + 2
        if marker in (0x01, 0xD8) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        if i + 4 > n:
            return None
        seg = int.from_bytes(data[i + 2:i + 4], "big")
        if seg < 2:
            return None
        if marker == 0xDA:  # начало данных — ищем следующий не-restart маркер
            i += 2 + seg
            while i + 1 < n and not (
                data[i] == 0xFF and data[i + 1] != 0x00
                and not 0xD0 <= data[i + 1] <= 0xD7
            ):
                i += 1
            continue
        i += 2 + seg
    return None


def extract_blobs(data: bytes, outdir: Path) -> list[str]:
    """Выдрать PNG/JPEG из бинарного .doc/.ppt по сигнатурам.

    wv и catdoc не умеют распаковывать Escher-блобы, но сами картинки лежат
    в файле целиком. Ищем сигнатуры и проверяем, что за ними идёт валидная
    структура: без проверки из случайного шума достаётся мусорный «JPEG», а
    он потом сдвигает все остальные картинки документа на одну позицию.
    """
    found: list[tuple[str, bytes]] = []
    png_sig = b"\x89PNG\r\n\x1a\n"
    jpeg_sig = b"\xff\xd8\xff"
    i = 0
    while i < len(data):
        nxt_png = data.find(png_sig, i)
        nxt_jpeg = data.find(jpeg_sig, i)
        candidates = [p for p in (nxt_png, nxt_jpeg) if p != -1]
        if not candidates:
            break
        start = min(candidates)
        if start == nxt_png:
            end = _png_end(data, start)
            if end is not None:
                found.append(("png", data[start:end]))
                i = end
                continue
        else:
            end = _jpeg_end(data, start)
            if end is not None and end - start >= MIN_JPEG:
                found.append(("jpg", data[start:end]))
                i = end
                continue
        i = start + 1

    outdir.mkdir(parents=True, exist_ok=True)
    names = []
    for index, (ext, blob) in enumerate(found, 1):
        name = f"img{index:03d}.{ext}"
        (outdir / name).write_bytes(blob)
        names.append(f"media/{name}")
    return names


def gallery(names: list[str], heading: str) -> str:
    if not names:
        return ""
    imgs = "".join(f'<img src="{html.escape(n)}" alt="">' for n in names)
    return f"<h2>{html.escape(heading)}</h2>\n<div class=\"gallery\">{imgs}</div>\n"


# --------------------------------------------------------------------------
# рендереры: каждый кладёт вспомогательные файлы в outdir и возвращает HTML

def render_pandoc(src: Path, outdir: Path, fmt: str) -> str:
    """Форматы, которые pandoc читает сам.

    --resource-path нужен, потому что pandoc работает из каталога кэша:
    без него относительная ![](pic.png) из markdown молча теряется.
    """
    markup = run(
        [PANDOC, "-f", fmt, "-t", "html5", "--mathml",
         f"--resource-path={src.parent}", "--extract-media=media",
         "-o", "-", str(src)],
        cwd=outdir,
    ).decode("utf-8", "replace")
    return sanitized_body(markup)


STRANGE_IMG = re.compile(r'<img\b[^>]*src="StrangeNoGraphicData"[^>]*>', re.I)


def render_doc(src: Path, outdir: Path) -> str:
    """Старый .doc: структура от wvHtml, картинки — из блобов.

    wvHtml пишется прямо в outdir: свои извлечённые картинки он кладёт рядом
    с html и ссылается на них относительно, а index.html лежит тут же.
    """
    target = outdir / "wv.html"
    try:
        run([WVHTML, "--charset=utf-8", f"--targetdir={outdir}",
             str(src), str(target)])
        markup = target.read_text("utf-8", "replace")
    except (RenderError, OSError):
        # OSError сюда попадает, когда wvHtml вышел с нулём, но файла не
        # написал: читать нечего, а документ показать всё равно надо.
        text = run([ANTIWORD, "-m", "UTF-8.txt", str(src)]).decode("utf-8", "replace")
        markup = "".join(
            f"<p>{html.escape(p)}</p>\n" for p in text.split("\n\n") if p.strip()
        )
    finally:
        target.unlink(missing_ok=True)

    body = sanitized_body(markup)
    names = extract_blobs(src.read_bytes(), outdir / "media")

    # wvHtml оставляет плейсхолдеры в нужных местах — подставляем по порядку.
    slots = len(STRANGE_IMG.findall(body))
    pool = iter(names)

    def swap(_match: re.Match[str]) -> str:
        nxt = next(pool, None)
        if nxt is None:
            return note("картинка не извлеклась")
        return f'<img src="{html.escape(nxt)}" alt="">'

    body = STRANGE_IMG.sub(swap, body)
    leftover = list(pool)

    head = ""
    if slots and len(names) != slots:
        head = note(
            f"Картинок в файле найдено {len(names)}, мест под них — {slots}. "
            "Часть могла сместиться."
        )
    return head + body + gallery(leftover, "Остальные изображения")


# Форма числа целиком, без опоры на float(): тот принимает inf, nan, 1_000
# и цифры других письменностей — в выгрузках такое встречается как текст.
# Пробел внутри допустим только как разделитель тысяч: «1 2 3» — не число.
NUMBER = re.compile(
    r"[+-]?(?:[0-9]{1,3}(?:\u00a0?[0-9]{3})+|[0-9]+)(?:[.,][0-9]+)?"
    r"(?:[eE][+-]?[0-9]+)?"
)


def is_number(text: str) -> bool:
    """Похоже ли содержимое ячейки на число (для выравнивания вправо)."""
    cleaned = text.strip().rstrip("%").strip().replace("\u00a0", " ")
    return bool(cleaned) and NUMBER.fullmatch(cleaned.replace(" ", "\u00a0")) is not None


def _table(rows: list[list[str]], caption: str) -> str:
    width = 0
    for row in rows:
        last = max((i for i, cell in enumerate(row) if cell.strip()), default=-1)
        width = max(width, last + 1)
    while rows and not any(cell.strip() for cell in rows[-1]):
        rows.pop()
    if not width or not rows:
        return f"<h2>{html.escape(caption)}</h2>\n<p>Лист пустой.</p>\n"

    head = ""
    if len(rows) > MAX_ROWS:
        head = note(f"Показаны первые {MAX_ROWS} строк из {len(rows)}.")
        rows = rows[:MAX_ROWS]

    out = [f"<table><caption>{html.escape(caption)}</caption><tbody>"]
    for row in rows:
        cells = []
        for cell in (row + [""] * width)[:width]:
            cell = cell.strip()
            cls = ' class="n"' if is_number(cell) else ""
            cells.append(f"<td{cls}>{html.escape(cell)}</td>")
        out.append("<tr>" + "".join(cells) + "</tr>")
    out.append("</tbody></table>")
    return head + "\n".join(out) + "\n"


def render_sheet(src: Path, outdir: Path) -> str:
    """Таблицы идём через CSV, а не через HTML-экспортёр gnumeric.

    Тот подгоняет текст под ширину колонки и молча округляет: 25 в узком
    столбце превращается в 3E+01. CSV отдаёт значения как есть, уже с
    применённым форматом ячейки (даты остаются датами).
    """
    work = outdir / "csv"
    work.mkdir(parents=True, exist_ok=True)
    try:
        run([SSCONVERT, "-S", "-T", "Gnumeric_stf:stf_csv",
             str(src), str(work / "%n-%s.csv")])

        def order(path: Path) -> tuple[int, str]:
            prefix, _, _ = path.name.partition("-")
            return (int(prefix) if prefix.isdigit() else 1 << 30, path.name)

        files = sorted(work.glob("*.csv"), key=order)
        if not files:
            raise RenderError("gnumeric не отдал ни одного листа")

        parts = []
        for path in files:
            _, _, name = path.name.partition("-")
            with path.open(newline="", encoding="utf-8", errors="replace") as fh:
                parts.append(_table(list(csv.reader(fh)), name.removesuffix(".csv")))
        return "\n".join(parts)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def _para_text(node: ET.Element) -> str:
    return "".join(t.text or "" for t in node.iterfind(".//a:t", NS)).strip()


def _paragraphs(node: ET.Element) -> list[tuple[int, str]]:
    """Абзацы фигуры вместе с уровнем вложенности списка."""
    out = []
    for para in node.iterfind(".//a:p", NS):
        text = _para_text(para)
        if not text:
            continue
        props = para.find("./a:pPr", NS)
        level = int(props.get("lvl", "0")) if props is not None else 0
        out.append((min(level, 3), text))
    return out


def _shape_html(shape: ET.Element) -> str:
    placeholder = shape.find("./p:nvSpPr/p:nvPr/p:ph", NS)
    kind = placeholder.get("type", "body") if placeholder is not None else "body"
    paras = _paragraphs(shape)
    if not paras:
        return ""
    if kind in ("title", "ctrTitle"):
        head = f"<h2>{html.escape(paras[0][1])}</h2>\n"
        rest = paras[1:]
    else:
        head, rest = "", paras
    # Абзацы остаются абзацами: списком их делает разметка исходника, а не
    # то, что их несколько. Уровень отражаем отступом.
    body = "".join(
        f'<p class="lvl{lvl}">{html.escape(text)}</p>\n' if lvl else
        f"<p>{html.escape(text)}</p>\n"
        for lvl, text in rest
    )
    return head + body


def _pic_html(pic: ET.Element, rels: dict[str, str], media: dict[str, str]) -> str:
    blip = pic.find(".//a:blip", NS)
    if blip is None:
        return ""
    rid = blip.get(f"{{{NS['r']}}}embed")
    target = rels.get(rid) if rid else None
    if not target or target not in media:
        # Внешняя ссылка или нестандартный путь — молча терять картинку
        # хуже, чем сказать о ней.
        return note("изображение не вложено в файл и не показано")
    return f'<p><img src="{html.escape(media[target])}" alt=""></p>\n'


def _tbl_html(frame: ET.Element) -> str:
    """Таблица слайда остаётся таблицей: плоский список ячеек нечитаем."""
    table = frame.find(".//a:tbl", NS)
    if table is None:
        return ""
    rows = []
    for tr in table.iterfind("./a:tr", NS):
        cells = "".join(
            "<td>" + "<br>".join(html.escape(t) for _, t in _paragraphs(tc)) + "</td>"
            for tc in tr.iterfind("./a:tc", NS)
        )
        rows.append(f"<tr>{cells}</tr>")
    return f"<table><tbody>{''.join(rows)}</tbody></table>\n" if rows else ""


def _walk(node: ET.Element, rels: dict[str, str], media: dict[str, str]) -> str:
    out = []
    for child in node:
        tag = child.tag.split("}")[-1]
        if tag == "sp":
            out.append(_shape_html(child))
        elif tag == "pic":
            out.append(_pic_html(child, rels, media))
        elif tag == "grpSp":
            out.append(_walk(child, rels, media))
        elif tag == "graphicFrame":
            inner = _tbl_html(child) or _walk(child, rels, media)
            if not inner:
                texts = [t for _, t in _paragraphs(child)]
                inner = "".join(f"<p>{html.escape(t)}</p>\n" for t in texts)
            out.append(inner)
    return "".join(out)


def _rels_for(zf: zipfile.ZipFile, slide: str) -> dict[str, str]:
    path = f"ppt/slides/_rels/{Path(slide).name}.rels"
    if path not in zf.namelist():
        return {}
    root = ET.fromstring(zf.read(path))
    rels = {}
    for rel in root:
        target = rel.get("Target", "")
        rid = rel.get("Id")
        if rid:
            rels[rid] = os.path.normpath(
                os.path.join("ppt/slides", target)).replace("\\", "/")
    return rels


def _slide_order(zf: zipfile.ZipFile) -> list[str]:
    """Порядок слайдов по sldIdLst; если его нет — по номеру в имени."""
    names = [n for n in zf.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)]
    try:
        pres = ET.fromstring(zf.read("ppt/presentation.xml"))
        rels = ET.fromstring(zf.read("ppt/_rels/presentation.xml.rels"))
        by_id = {
            r.get("Id"): os.path.normpath(
                os.path.join("ppt", r.get("Target", ""))).replace("\\", "/")
            for r in rels
        }
        ordered = [
            by_id.get(sid.get(f"{{{NS['r']}}}id"))
            for sid in pres.iterfind("./p:sldIdLst/p:sldId", NS)
        ]
        ordered = [n for n in ordered if n in names]
        if ordered:
            return ordered
    except (KeyError, ET.ParseError):
        pass
    return sorted(names, key=lambda n: int(re.search(r"(\d+)", Path(n).stem).group(1)))


def render_pptx(src: Path, outdir: Path) -> str:
    media_dir = outdir / "media"
    media_dir.mkdir(parents=True, exist_ok=True)
    try:
        zf = zipfile.ZipFile(src)
    except zipfile.BadZipFile:
        raise RenderError("это не .pptx — архив не читается") from None
    with zf:
        media = {}
        budget = MAX_MEDIA_BYTES
        skipped = 0
        for info in zf.infolist():
            name = info.filename
            if not name.startswith("ppt/media/") or name.endswith("/"):
                continue
            # Размер сверяем по заголовку, до распаковки: иначе zip-бомба
            # разворачивается в кэш целиком.
            if info.file_size > budget:
                skipped += 1
                continue
            budget -= info.file_size
            base = Path(name).name
            (media_dir / base).write_bytes(zf.read(name))
            media[name] = f"media/{base}"
        parts = []
        if skipped:
            parts.append(note(
                f"Не распаковано вложений: {skipped} — презентация просит "
                "больше места, чем разумно держать в кэше."
            ))
        for number, slide in enumerate(_slide_order(zf), 1):
            try:
                root = ET.fromstring(zf.read(slide))
            except ET.ParseError:
                parts.append(
                    f'<section class="slide"><span class="num">Слайд {number}</span>\n'
                    + note("слайд повреждён и не разобрался") + "</section>"
                )
                continue
            tree = root.find(".//p:cSld/p:spTree", NS)
            body = _walk(tree, _rels_for(zf, slide), media) if tree is not None else ""
            if not body.strip():
                body = note("Слайд без текста и растровых картинок.")
            parts.append(
                f'<section class="slide"><span class="num">Слайд {number}</span>\n'
                f"{body}</section>"
            )
    if not parts:
        raise RenderError("в презентации не нашлось слайдов")
    return "\n".join(parts)


def render_ppt(src: Path, outdir: Path) -> str:
    """Бинарный .ppt: текста от catppt может не быть, картинки — из блобов."""
    try:
        text = run([CATPPT, str(src)]).decode("utf-8", "replace").strip()
    except RenderError:
        text = ""
    names = extract_blobs(src.read_bytes(), outdir / "media")
    if not text and not names:
        raise RenderError("в файле не нашлось ни текста, ни картинок")
    parts = [note(
        "Старый формат .ppt: разметка слайдов не читается без полноценного "
        "офиса — ниже текст и картинки из файла."
    )]
    parts += [f"<p>{html.escape(p)}</p>" for p in text.split("\n\n") if p.strip()]
    parts.append(gallery(names, "Изображения"))
    return "\n".join(parts)


# --------------------------------------------------------------------------
# реестр форматов

class Format(NamedTuple):
    kind: str                                   # метка в шапке страницы
    render: Callable[[Path, Path], str]         # (исходник, каталог) -> HTML
    wide: bool = False                          # альбомная страница


def _pandoc(fmt: str) -> Callable[[Path, Path], str]:
    def render(src: Path, outdir: Path) -> str:
        return render_pandoc(src, outdir, fmt)
    return render


FORMATS: dict[str, Format] = {
    ".docx": Format("docx", _pandoc("docx")),
    ".odt": Format("odt", _pandoc("odt")),
    ".rtf": Format("rtf", _pandoc("rtf")),
    ".epub": Format("epub", _pandoc("epub")),
    ".fb2": Format("fb2", _pandoc("fb2")),
    # Читатель pandoc'а, а не gfm: таблицы и $math$ он понимает из коробки.
    ".md": Format("md", _pandoc("markdown")),
    ".markdown": Format("md", _pandoc("markdown")),
    ".doc": Format("doc", render_doc),
    ".xlsx": Format("xlsx", render_sheet, wide=True),
    ".xlsm": Format("xlsm", render_sheet, wide=True),
    ".xls": Format("xls", render_sheet, wide=True),
    ".ods": Format("ods", render_sheet, wide=True),
    ".gnumeric": Format("gnumeric", render_sheet, wide=True),
    ".csv": Format("csv", render_sheet, wide=True),
    ".tsv": Format("tsv", render_sheet, wide=True),
    ".pptx": Format("pptx", render_pptx),
    ".ppt": Format("ppt", render_ppt),
}


def pick_format(src: Path) -> Format:
    fmt = FORMATS.get(src.suffix.lower())
    if fmt is None:
        raise RenderError(f"не знаю, чем открыть {src.suffix or 'файл без расширения'}")
    return fmt


# --------------------------------------------------------------------------
# печать

# Сбой запуска, который лечится отключением песочницы: ядро без
# unprivileged userns. Всё остальное отключением песочницы не чинится.
# Сверяем по полному stderr, а не по сообщению для человека: chromium пишет
# после этой строки ещё несколько, и обрезка до последних двух её съедает.
SANDBOX_TROUBLE = re.compile(
    r"Failed to move to new namespace|namespace sandbox|clone\(\) returned|"
    r"No usable sandbox|SUID sandbox|CLONE_NEWUSER|"
    r"sandbox.*Operation not permitted", re.I)


def _chromium_cmd(index: Path, pdf: Path, profile: Path) -> list[str]:
    return [
        CHROMIUM,
        "--headless",
        f"--user-data-dir={profile}",
        "--no-first-run",
        "--disable-extensions",
        # Документ не должен ходить в сеть: ни трекинг-пикселей, ни утечки
        # содержимого на чужой хост.
        "--host-resolver-rules=MAP * ~NOTFOUND",
        "--disable-background-networking",
        "--disable-remote-fonts",
        "--virtual-time-budget=20000",
        "--no-pdf-header-footer",
        f"--print-to-pdf={pdf}",
        index.as_uri(),
    ]


def to_pdf(index: Path, pdf: Path) -> None:
    """Напечатать готовую страницу в PDF headless-хромиумом.

    Он уже стоит в системе и умеет и MathML, и картинки, так что отдельный
    html2pdf-движок не нужен. Профиль временный: общий каталог заставлял
    параллельные запуски драться за ProcessSingleton и падать.
    """
    profile = Path(tempfile.mkdtemp(prefix="gdoc-chromium-"))
    try:
        cmd = _chromium_cmd(index, pdf, profile)
        try:
            run(cmd, timeout=PRINT_TIMEOUT)
        except RenderError as first:
            if not SANDBOX_TROUBLE.search(first.raw or str(first)):
                raise
            print(f"gdoc: {first}; печатаю без песочницы chromium",
                  file=sys.stderr)
            run(cmd + ["--no-sandbox"], timeout=PRINT_TIMEOUT)
    finally:
        shutil.rmtree(profile, ignore_errors=True)

    if not pdf.exists() or pdf.stat().st_size == 0:
        raise RenderError("chromium не записал PDF")


# --------------------------------------------------------------------------
# кэш

def cache_root() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "gdoc"


def slugify(stem: str) -> str:
    """Имя, безопасное для каталога кэша и для заголовка окна zathura."""
    return re.sub(r"[^\w.-]+", "_", stem).strip("._-")[:48] or "doc"


@functools.cache
def _source_digest() -> str:
    """Отпечаток собственного кода.

    Правка логики рендера меняет результат так же, как правка CSS, — без
    этого запись, собранная прежней версией, переиспользовалась бы молча.
    Если прочитать себя не удалось (zipapp, frozen-сборка), инвалидация по
    коду отключается — под nix-обёрткой путь всегда настоящий, так что это
    только про нештатный запуск.
    """
    try:
        return hashlib.sha1(Path(__file__).read_bytes()).hexdigest()
    except (OSError, NameError):
        return "исходник недоступен"


def renderer_fingerprint() -> str:
    """От чего зависит результат, кроме самого документа.

    Store-пути конвертеров меняются при их обновлении, вёрстка — при правке
    CSS и скрипта, поведение — при правке кода. Так кэш инвалидируется сам,
    без счётчика версии, который надо не забыть поднять руками.
    """
    material = "\0".join(
        [PANDOC, WVHTML, SSCONVERT, CATPPT, ANTIWORD, CHROMIUM,
         PAGE_CSS, PAGE_JS, _source_digest()]
    )
    return hashlib.sha1(material.encode()).hexdigest()[:12]


def cache_dir(src: Path) -> Path:
    st = src.stat()
    key = f"{renderer_fingerprint()}|{src.resolve()}|{st.st_mtime_ns}|{st.st_size}"
    digest = hashlib.sha1(key.encode()).hexdigest()[:16]
    return cache_root() / f"{slugify(src.stem)}-{digest}"


def prune_cache(keep: int = CACHE_KEEP) -> None:
    """Вытеснить лишнее и подобрать за упавшими запусками.

    Свежие записи не трогаем вовсе: `build` обновляет время доступа сразу
    перед вызовом, так что «свежая» — это ровно та, которой прямо сейчас
    пользуется кто-то (в том числе другой процесс, до чьих переменных
    отсюда не дотянуться).
    """
    root = cache_root()
    if not root.is_dir():
        return
    now = time.time()
    entries = []
    for entry in root.iterdir():
        try:
            if not entry.is_dir():
                continue
            mtime = entry.stat().st_mtime
        except OSError:
            continue  # каталог убрал другой процесс
        if entry.name.startswith("."):
            # Недособранная запись. Живой процесс дочистит её сам, а вот
            # убитый — уже никогда, поэтому старое подбираем здесь.
            if now - mtime > STAGING_MAX_AGE:
                shutil.rmtree(entry, ignore_errors=True)
            continue
        if now - mtime < CACHE_MIN_AGE:
            continue
        entries.append((mtime, entry))
    entries.sort(reverse=True)
    for _, stale in entries[keep:]:
        shutil.rmtree(stale, ignore_errors=True)


def build(src: Path, force: bool = False, as_pdf: bool = True) -> Path:
    """Собрать документ и вернуть путь к готовому файлу в кэше.

    Оба артефакта публикуются атомарно: каталог собирается рядом под
    точечным именем и переезжает на место одним rename, PDF пишется во
    временный файл и тоже переименовывается. Поэтому параллельные запуски
    не мешают друг другу, а прерванный на середине не оставляет в кэше
    полуфабрикат, который потом переиспользуется молча и навсегда.
    """
    out = cache_dir(src)
    index = out / "index.html"
    # Имя PDF видно в заголовке zathura, поэтому берём его от исходника.
    pdf = out / f"{slugify(src.stem)}.pdf"

    # Формат выясняем до всякой работы: на незнакомом расширении незачем
    # трогать кэш и плодить каталоги.
    fmt = pick_format(src)
    if src.stat().st_size == 0:
        # Иначе часть конвертеров молча отдаёт пустую страницу и rc=0, и
        # пользователь получает чистый лист вместо объяснения.
        raise RenderError("файл пустой")

    if force:
        shutil.rmtree(out, ignore_errors=True)
    elif out.exists() and not index.exists():
        # Запись от прежних версий, собиравших кэш не атомарно.
        shutil.rmtree(out, ignore_errors=True)

    if not index.exists():
        staging = out.with_name(f".tmp-{os.getpid()}-{out.name}")
        shutil.rmtree(staging, ignore_errors=True)
        staging.mkdir(parents=True)
        try:
            body = fmt.render(src, staging)
            (staging / "index.html").write_text(
                page(src.name, fmt.kind, body, fmt.wide), "utf-8")
            try:
                staging.replace(out)
            except OSError as exc:
                # Каталог уже занят — нас опередил параллельный запуск, его
                # результат ничем не хуже. Любая другая причина (кончилось
                # место, раздел только для чтения) должна быть названа.
                if exc.errno not in (errno.ENOTEMPTY, errno.EEXIST):
                    raise RenderError(f"не записать в кэш: {exc.strerror}") from None
        finally:
            shutil.rmtree(staging, ignore_errors=True)

    if not index.exists():
        raise RenderError("не удалось положить результат в кэш")

    # Отметка доступа: без неё вытеснение шло бы по дате сборки и выбрасывало
    # документ, который открывают каждый день, наравне с забытым.
    try:
        os.utime(out)
    except OSError:
        pass
    prune_cache()
    if not as_pdf:
        return index

    try:
        ready = pdf.stat().st_size > 0
    except OSError:
        ready = False
    if not ready:
        draft = out / f".tmp-{os.getpid()}.pdf"
        try:
            to_pdf(index, draft)
            draft.replace(pdf)
        finally:
            draft.unlink(missing_ok=True)
    return pdf


# --------------------------------------------------------------------------
# командная строка

def fail(message: str) -> None:
    """Сообщить об ошибке.

    Только stderr: из .desktop его никто не увидит, и документ, который не
    отрисовался, оттуда выглядит как ничего не произошло. Это осознанный
    размен — уведомления не стоят отдельной зависимости ради одного случая.
    """
    print(f"gdoc: {message}", file=sys.stderr)


def looks_like_dir(raw: str) -> bool:
    """Просили каталог? Слэш проверяем по исходной строке.

    Path его молча срезает, так что `Path(raw).name` про намерение
    пользователя уже ничего не знает.
    """
    return raw.endswith(os.sep) or Path(raw).expanduser().is_dir()


def export(pdf: Path, src: Path, raw_dest: str, overwrite: bool) -> Path:
    """Положить готовый PDF туда, куда попросили в --out."""
    dest = Path(raw_dest).expanduser()
    if looks_like_dir(raw_dest):
        final = dest / (src.stem + ".pdf")
    else:
        final = dest if dest.suffix.lower() == ".pdf" else dest.with_name(dest.name + ".pdf")
    if final.exists() and not overwrite:
        raise RenderError(f"{final} уже есть — заменить можно с --overwrite")
    final.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(pdf, final)
    return final


def launcher(args: argparse.Namespace) -> tuple[str, Callable[[Path], list[str]]]:
    """Чем открывать результат и с какими аргументами."""
    if args.html:
        browser = shutil.which(args.browser) or args.browser
        name = Path(browser).name

        def open_html(target: Path) -> list[str]:
            if "chrom" in name:
                return [browser, f"--app={target.as_uri()}"]
            return [browser, target.as_uri()]

        return browser, open_html

    viewer = shutil.which(args.viewer) or args.viewer
    return viewer, lambda target: [viewer, str(target)]


def parse_args(argv: list[str] | None) -> tuple[argparse.ArgumentParser, argparse.Namespace]:
    ap = argparse.ArgumentParser(
        prog="gdoc",
        description="Открыть .doc/.docx/.ppt/.pptx/.xls/.xlsx/.odt/.md в zathura.",
    )
    # nargs="*", иначе --clean нельзя вызвать без файла, как обещает --help.
    ap.add_argument("files", nargs="*", metavar="ФАЙЛ")
    ap.add_argument("-f", "--force", action="store_true",
                    help="перерисовать мимо кэша")
    ap.add_argument("-y", "--overwrite", action="store_true",
                    help="с --out: заменить файл, если он уже есть")
    ap.add_argument("-p", "--path", action="store_true",
                    help="напечатать путь в кэше, не открывать")
    ap.add_argument("-o", "--out", metavar="КУДА",
                    help="сохранить PDF насовсем: каталог или имя файла "
                         "(каталог '.' — текущий); окно при этом не открывается")
    ap.add_argument("--html", action="store_true",
                    help="не печатать PDF, а открыть HTML в браузере")
    ap.add_argument("--viewer", default=os.environ.get("GDOC_VIEWER", "zathura"),
                    help="чем смотреть PDF (по умолчанию zathura)")
    ap.add_argument("-b", "--browser", default=os.environ.get("GDOC_BROWSER", "chromium"),
                    help="чем открывать --html")
    ap.add_argument("--clean", action="store_true", help="очистить кэш и выйти")
    args = ap.parse_args(argv)

    if args.clean:
        if args.files:
            ap.error("--clean чистит кэш целиком, файлы ему не нужны")
        return ap, args
    if not args.files:
        ap.error("нужен хотя бы один ФАЙЛ")
    if args.out and args.html:
        ap.error("--out сохраняет PDF, с --html он не имеет смысла")
    if args.out and args.path:
        ap.error("--out и --path просят разного: выберите что-то одно")
    if args.out and len(args.files) > 1 and not looks_like_dir(args.out):
        ap.error(f"файлов несколько — в --out нужен каталог, а не {args.out}")
    return ap, args


def main(argv: list[str] | None = None) -> int:
    _, args = parse_args(argv)

    if args.clean:
        shutil.rmtree(cache_root(), ignore_errors=True)
        print("кэш очищен")
        return 0

    rc = 0
    ready: list[tuple[Path, Path]] = []
    for name in args.files:
        # Абсолютный путь обязателен: конвертеры работают из каталога кэша,
        # и относительное имя разрешалось бы уже от него.
        src = Path(os.path.abspath(os.path.expanduser(name)))
        if not src.is_file():
            fail(f"не файл: {src}")
            rc = 1
            continue
        try:
            ready.append((src, build(src, args.force, as_pdf=not args.html)))
        except RenderError as exc:
            fail(f"{src.name}: {exc}")
            rc = 1
        except OSError as exc:
            fail(f"{src.name}: {exc.strerror or exc}")
            rc = 1
        except Exception as exc:  # noqa: BLE001 — показать причину, а не трейс
            fail(f"{src.name}: {type(exc).__name__}: {exc}")
            rc = 1

    if not ready:
        return rc or 1

    if args.out:
        for src, pdf in ready:
            try:
                print(export(pdf, src, args.out, args.overwrite))
            except (RenderError, OSError) as exc:
                reason = exc.strerror if isinstance(exc, OSError) else exc
                fail(f"не записать из {src.name}: {reason}")
                rc = 1
        return rc

    if args.path:
        for _, target in ready:
            print(target)
        return rc

    program, argv_for = launcher(args)
    if shutil.which(program) is None and not os.access(program, os.X_OK):
        fail(f"не найдена программа {program}")
        return 1
    for _, target in ready:
        subprocess.Popen(
            argv_for(target),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    return rc


if __name__ == "__main__":
    sys.exit(main())
