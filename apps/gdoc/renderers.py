"""Конвертеры форматов: каждый отдаёт готовую разметку документа."""

from __future__ import annotations

import csv
import html
import os
import re
import shutil
import zipfile
from pathlib import Path
from typing import Callable, NamedTuple
from xml.etree import ElementTree as ET

from blobs import extract_blobs, gallery
from common import (ANTIWORD, CATPPT, PANDOC, PRINT_TIMEOUT, SSCONVERT, TYPST,
                    TYPST_FONTS, WVHTML, RenderError, run)
from page import note
from sanitize import sanitized_body


NS = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}


# Ячейка CSV может быть длиннее дефолтных 128 КБ — иначе csv.reader бросает
# Error и лист не открывается вовсе.
csv.field_size_limit(16 * 1024 * 1024)


# Выше этого лист обрезается: PDF на сто тысяч строк бесполезен и собирается
# минутами.
MAX_ROWS = 5000


# Потолок на распаковку вложений презентации, чтобы zip-бомба не легла
# в кэш целиком.
MAX_MEDIA_BYTES = 256 * 1024 * 1024


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


# Это zathura читает сама, и лучше нас: epub она листает как книгу, а не как
# простыню на двести страниц, а PDF незачем печатать второй раз. Список
# сверен с плагинами, которые собраны в zathura-with-plugins (pdf-mupdf, djvu,
# ps, cb); со сторонним --viewer он может и не совпасть.
#
# .fb2 mupdf тоже открывает, но почти без оформления, поэтому его мы
# по-прежнему рисуем сами.
VIEWER_READS = frozenset({
    ".pdf", ".ps", ".eps", ".epub", ".mobi", ".oxps",
    ".djvu", ".djv", ".cbz", ".cbr", ".cb7", ".cbt",
})


# Сырой typst из markdown пропускать нельзя: pandoc отдаёт блок ```{=typst}
# компилятору как код, а #read("/etc/passwd") вклеит в PDF любой файл,
# доступный пользователю. Этот читатель гасит такие блоки на входе,
# превращая их в обычный текст.
TYPST_READER = "markdown-raw_attribute"


class Format(NamedTuple):
    kind: str                                   # метка в шапке страницы
    render: Callable[[Path, Path], str]         # (исходник, каталог) -> HTML
    wide: bool = False                          # альбомная страница
    # Свой путь в PDF, мимо страницы и браузера: (исходник, каталог, PDF).
    # HTML при этом всё равно собирается — он нужен для --html и служит
    # отметкой готовности записи в кэше.
    pdf: Callable[[Path, Path, Path], None] | None = None


def _typst_cmd(doc: Path, root: Path, pdf: Path) -> list[str]:
    cmd = [TYPST, "compile", "--root", str(root)]
    if TYPST_FONTS:
        # Иначе результат зависит от шрифтов машины: моноширинный без
        # кириллицы молча подменяется засечным, и код в тексте не отличить.
        cmd += ["--font-path", TYPST_FONTS, "--ignore-system-fonts"]
    return cmd + [str(doc), str(pdf)]


def render_typst(src: Path, workdir: Path, pdf: Path) -> None:
    """Markdown -> PDF через typst, минуя HTML и браузер.

    Формулы typst набирает настоящим математическим шрифтом, тогда как в
    MathML'е chromium радикал наезжает на дробь. Картинки уже распакованы в
    workdir html-проходом, а --root запирает чтение этим каталогом — вторая
    преграда на случай, если сырой typst всё-таки просочится.
    """
    doc = workdir / f".tmp-{os.getpid()}.typ"
    try:
        run([PANDOC, "-f", TYPST_READER, "-t", "typst",
             f"--resource-path={src.parent}", "--extract-media=media",
             "-o", doc.name, str(src)], cwd=workdir)
        run(_typst_cmd(doc, workdir, pdf), timeout=PRINT_TIMEOUT)
    finally:
        doc.unlink(missing_ok=True)
    if not pdf.exists() or pdf.stat().st_size == 0:
        raise RenderError("typst не записал PDF")


def _pandoc(fmt: str) -> Callable[[Path, Path], str]:
    def render(src: Path, outdir: Path) -> str:
        return render_pandoc(src, outdir, fmt)
    return render


FORMATS: dict[str, Format] = {
    ".docx": Format("docx", _pandoc("docx")),
    ".odt": Format("odt", _pandoc("odt")),
    ".rtf": Format("rtf", _pandoc("rtf")),
    ".fb2": Format("fb2", _pandoc("fb2")),
    # Читатель pandoc'а, а не gfm: таблицы и $math$ он понимает из коробки.
    ".md": Format("md", _pandoc("markdown"), pdf=render_typst),
    ".markdown": Format("md", _pandoc("markdown"), pdf=render_typst),
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
