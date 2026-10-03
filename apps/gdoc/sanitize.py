"""Очистка разметки, пришедшей от конвертера.

Доверять ей нельзя: pandoc пропускает сырой HTML из markdown и epub
насквозь, так что документ способен принести <script>, <iframe file://>
и onerror=. Отсюда денилист тегов, фильтр ссылок и аллоулист стилей.
"""

from __future__ import annotations

import html
import re
from collections import Counter
from html.parser import HTMLParser
from typing import Iterable

from page import note


# Глубже этого разметку уже никто не писал осмысленно, а очистка на
# вложенности в десятки тысяч тегов съедает секунды CPU.
MAX_DEPTH = 200


# Имя тега берётся из чужого документа и уезжает в вывод — пропускаем
# только то, что точно является именем.
TAG_NAME = re.compile(r"[a-zA-Z][a-zA-Z0-9:._-]*")


# Растровые data-картинки безопасны, в отличие от svg+xml, который
# является документом и умеет нести скрипты.
DATA_IMAGE = re.compile(r"data:image/(png|jpe?g|gif|webp|bmp|avif|tiff);")


# Цветовые функции CSS: аргументы у них только числовые, так что вырезать
# их из проверки значения безопасно.
COLOR_FN = re.compile(r"(?:rgba?|hsla?)\([0-9,.%/\s+-]*\)", re.I)


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
