"""Кэш собранных документов и его атомарное пополнение."""

from __future__ import annotations

import errno
import functools
import hashlib
import os
import re
import shutil
import time
from pathlib import Path

from common import (ANTIWORD, CATPPT, CHROMIUM, PANDOC, PRINT_TIMEOUT,
                    RUN_TIMEOUT, SSCONVERT, WVHTML, RenderError)
from page import PAGE_CSS, PAGE_JS, page
from printing import to_pdf
from renderers import pick_format


# Сколько собранных документов держим в кэше.
CACHE_KEEP = 40


# Дольше этого недособранный каталог живым процессом держаться не может:
# потолок жизни запуска — RUN_TIMEOUT плюс PRINT_TIMEOUT.
STAGING_MAX_AGE = RUN_TIMEOUT + PRINT_TIMEOUT + 60


# Запись моложе этого кто-то прямо сейчас читает или печатает: build
# обновляет время доступа перед самой печатью.
CACHE_MIN_AGE = 120


def cache_root() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "gdoc"


def slugify(stem: str) -> str:
    """Имя, безопасное для каталога кэша и для заголовка окна zathura."""
    return re.sub(r"[^\w.-]+", "_", stem).strip("._-")[:48] or "doc"


@functools.cache
def _source_digest() -> str:
    """Отпечаток кода приложения — всех модулей рядом с этим.

    Правка логики рендера меняет результат так же, как правка CSS, — без
    этого запись, собранная прежней версией, переиспользовалась бы молча.
    Считать только по cache.py нельзя: рендерят соседние модули.

    Имя файла идёт в хэш вместе с содержимым, иначе переименование модуля
    осталось бы незамеченным. Если прочитать себя не удалось (zipapp,
    frozen-сборка), инвалидация по коду отключается — под nix-обёрткой путь
    всегда настоящий, так что это только про нештатный запуск.
    """
    try:
        digest = hashlib.sha1()
        for module in sorted(Path(__file__).resolve().parent.glob("*.py")):
            digest.update(module.name.encode())
            digest.update(module.read_bytes())
        return digest.hexdigest()
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
