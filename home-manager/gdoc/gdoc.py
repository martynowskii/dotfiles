#!/usr/bin/env python3
"""gdoc — рендерит офисные документы в HTML и открывает их в браузере.

Конвертеры подбираются по расширению: pandoc для OOXML/ODF, wvHtml для
старого .doc, ssconvert для таблиц, свой обход XML для .pptx. Результат
складывается в кэш и переиспользуется, пока файл не изменился.
"""

import argparse
import csv
import hashlib
import html
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

# Кэш инвалидируется целиком при смене версии — поднимать при правках рендера.
RENDERER = "6"

NS = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "pr": "http://schemas.openxmlformats.org/package/2006/relationships",
}

PANDOC_FORMATS = {
    ".docx": "docx",
    ".odt": "odt",
    ".rtf": "rtf",
    ".epub": "epub",
    ".fb2": "fb2",
}
SHEET_EXTS = {".xlsx", ".xls", ".ods", ".csv", ".tsv", ".gnumeric", ".xlsm"}


def tool(env_var, name):
    """Путь до утилиты: из окружения (его задаёт nix-обёртка) либо из PATH."""
    return os.environ.get(env_var) or shutil.which(name) or name


PANDOC = tool("GDOC_PANDOC", "pandoc")
WVHTML = tool("GDOC_WVHTML", "wvHtml")
SSCONVERT = tool("GDOC_SSCONVERT", "ssconvert")
CATPPT = tool("GDOC_CATPPT", "catppt")
ANTIWORD = tool("GDOC_ANTIWORD", "antiword")


class RenderError(Exception):
    pass


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
"""


def page(title, kind, body, wide=False):
    w = " topbar--wide" if wide else ""
    s = " sheet--wide" if wide else ""
    return (
        '<!DOCTYPE html>\n<html lang="ru"><head><meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"<title>{html.escape(title)}</title>\n<style>{PAGE_CSS}</style></head>\n"
        f'<body>\n<div class="topbar{w}"><b>{html.escape(title)}</b>'
        f'<span class="kind">{html.escape(kind)}</span></div>\n'
        f'<main class="sheet{s}">\n{body}\n</main>\n</body></html>\n'
    )


BODY_RE = re.compile(r"<body[^>]*>(.*)</body>", re.S | re.I)
STYLE_RE = re.compile(r"<style[^>]*>.*?</style>", re.S | re.I)
COMMENT_RE = re.compile(r"<!--.*?-->", re.S)


def body_of(markup):
    """Вытащить содержимое <body>, отбросив чужие стили."""
    m = BODY_RE.search(markup)
    return STYLE_RE.sub("", m.group(1) if m else markup)


def run(cmd, **kw):
    kw.setdefault("stdout", subprocess.PIPE)
    kw.setdefault("stderr", subprocess.PIPE)
    proc = subprocess.run(cmd, **kw)
    if proc.returncode != 0:
        err = (proc.stderr or b"").decode("utf-8", "replace").strip()
        raise RenderError(f"{Path(cmd[0]).name}: {err.splitlines()[-1] if err else 'код ' + str(proc.returncode)}")
    return proc.stdout or b""


# --------------------------------------------------------------------------
# картинки из бинарных форматов

def extract_blobs(data, outdir):
    """Выдрать PNG/JPEG из бинарного .doc/.ppt по сигнатурам.

    wv и catdoc не умеют распаковывать Escher-блобы, но сами картинки лежат
    в файле целиком, так что их можно найти по заголовкам и границам.
    """
    found = []
    i, n = 0, len(data)
    while i < n:
        if data.startswith(b"\x89PNG\r\n\x1a\n", i):
            j, ok = i + 8, False
            while j + 8 <= n:
                ln = int.from_bytes(data[j:j + 4], "big")
                typ = data[j + 4:j + 8]
                if ln > n:
                    break
                j += 8 + ln + 4
                if typ == b"IEND":
                    ok = True
                    break
            if ok:
                found.append(("png", data[i:j]))
                i = j
                continue
        if data.startswith(b"\xff\xd8\xff", i):
            j, ok = i + 2, False
            while j + 4 <= n:
                if data[j] != 0xFF:
                    j += 1
                    continue
                m = data[j + 1]
                if m == 0xD9:
                    j += 2
                    ok = True
                    break
                if m in (0x01, 0xD8) or 0xD0 <= m <= 0xD7:
                    j += 2
                    continue
                if m == 0xDA:  # начало данных — до следующего не-restart маркера
                    j += 2 + int.from_bytes(data[j + 2:j + 4], "big")
                    while j + 1 < n and not (
                        data[j] == 0xFF and data[j + 1] != 0x00
                        and not 0xD0 <= data[j + 1] <= 0xD7
                    ):
                        j += 1
                    continue
                j += 2 + int.from_bytes(data[j + 2:j + 4], "big")
            if ok and j - i > 1000:  # мелочь — это чаще всего превью-иконки
                found.append(("jpg", data[i:j]))
                i = j
                continue
        i += 1

    outdir.mkdir(parents=True, exist_ok=True)
    names = []
    for k, (ext, blob) in enumerate(found, 1):
        name = f"img{k:03d}.{ext}"
        (outdir / name).write_bytes(blob)
        names.append(f"media/{name}")
    return names


def gallery(names, heading):
    if not names:
        return ""
    imgs = "".join(f'<img src="{html.escape(n)}" alt="">' for n in names)
    return f'<h2>{html.escape(heading)}</h2>\n<div class="gallery">{imgs}</div>\n'


# --------------------------------------------------------------------------
# рендереры

def render_pandoc(src, outdir, fmt):
    markup = run(
        [PANDOC, "-f", fmt, "-t", "html5", "--mathml",
         "--extract-media=media", "-o", "-", str(src)],
        cwd=outdir,
    ).decode("utf-8", "replace")
    return markup, False


STRANGE_IMG = re.compile(r'<img\b[^>]*src="StrangeNoGraphicData"[^>]*>', re.I)


def render_doc(src, outdir):
    """Старый .doc: структура от wvHtml, картинки — из блобов."""
    work = outdir / "wv"
    work.mkdir(parents=True, exist_ok=True)
    target = work / "doc.html"
    try:
        run([WVHTML, "--charset=utf-8", f"--targetdir={work}", str(src), str(target)])
        markup = target.read_text("utf-8", "replace")
    except (RenderError, FileNotFoundError):
        text = run([ANTIWORD, "-m", "UTF-8.txt", str(src)]).decode("utf-8", "replace")
        paras = "".join(f"<p>{html.escape(p)}</p>\n" for p in text.split("\n\n") if p.strip())
        markup = f"<body>{paras}</body>"

    # В хвосте wvHtml прячет свои баннеры в комментарии — они только мешают.
    body = COMMENT_RE.sub("", body_of(markup))
    names = extract_blobs(src.read_bytes(), outdir / "media")

    # wvHtml оставляет плейсхолдеры в нужных местах — подставляем по порядку.
    slots = len(STRANGE_IMG.findall(body))
    pool = iter(names)

    def swap(_m):
        nxt = next(pool, None)
        if nxt is None:
            return '<p class="note">картинка не извлеклась</p>'
        return f'<img src="{html.escape(nxt)}" alt="">'

    body = STRANGE_IMG.sub(swap, body)
    leftover = list(pool)

    notes = ""
    if slots and len(names) != slots:
        notes = (
            f'<p class="note">Картинок в файле найдено {len(names)}, '
            f"мест под них — {slots}. Часть могла сместиться.</p>\n"
        )
    return notes + body + gallery(leftover, "Остальные изображения"), False


NUMERIC = re.compile(r"^-?[\d\s]*[.,]?\d+\s*%?$")
MAX_ROWS = 5000


def _table(rows, caption):
    width = 0
    for r in rows:
        last = max((i for i, c in enumerate(r) if c.strip()), default=-1)
        width = max(width, last + 1)
    while rows and not any(c.strip() for c in rows[-1]):
        rows.pop()
    if not width or not rows:
        return f"<h2>{html.escape(caption)}</h2>\n<p>Лист пустой.</p>\n"

    note = ""
    if len(rows) > MAX_ROWS:
        note = (
            f'<p class="note">Показаны первые {MAX_ROWS} строк из {len(rows)}.</p>\n'
        )
        rows = rows[:MAX_ROWS]

    out = [f"<table><caption>{html.escape(caption)}</caption><tbody>"]
    for r in rows:
        cells = []
        for c in (r + [""] * width)[:width]:
            c = c.strip()
            cls = ' class="n"' if c and NUMERIC.match(c) else ""
            cells.append(f"<td{cls}>{html.escape(c)}</td>")
        out.append("<tr>" + "".join(cells) + "</tr>")
    out.append("</tbody></table>")
    return note + "\n".join(out) + "\n"


def render_sheet(src, outdir):
    """Таблицы идём через CSV, а не через HTML-экспортёр gnumeric.

    Тот подгоняет текст под ширину колонки и молча округляет: 25 в узком
    столбце превращается в 3E+01. CSV отдаёт значения как есть, уже с
    применённым форматом ячейки (даты остаются датами).
    """
    work = outdir / "csv"
    work.mkdir(parents=True, exist_ok=True)
    run([SSCONVERT, "-S", "-T", "Gnumeric_stf:stf_csv", str(src), str(work / "%n-%s.csv")],
        stderr=subprocess.DEVNULL)

    files = sorted(work.glob("*.csv"), key=lambda p: int(p.name.split("-", 1)[0]))
    if not files:
        raise RenderError("gnumeric не отдал ни одного листа")

    parts = []
    for f in files:
        name = f.name.split("-", 1)[1].removesuffix(".csv")
        with f.open(newline="", encoding="utf-8", errors="replace") as fh:
            parts.append(_table(list(csv.reader(fh)), name))
    return "\n".join(parts), True


def _para_text(node):
    return "".join(t.text or "" for t in node.iterfind(".//a:t", NS)).strip()


def _shape_html(sp):
    ph = sp.find("./p:nvSpPr/p:nvPr/p:ph", NS)
    kind = ph.get("type", "body") if ph is not None else "body"
    paras = [_para_text(p) for p in sp.iterfind(".//a:p", NS)]
    paras = [p for p in paras if p]
    if not paras:
        return ""
    if kind in ("title", "ctrTitle"):
        return f"<h2>{html.escape(paras[0])}</h2>\n" + "".join(
            f"<p>{html.escape(p)}</p>\n" for p in paras[1:]
        )
    if len(paras) > 1:
        items = "".join(f"<li>{html.escape(p)}</li>" for p in paras)
        return f"<ul>{items}</ul>\n"
    return f"<p>{html.escape(paras[0])}</p>\n"


def _pic_html(pic, rels, media):
    blip = pic.find(".//a:blip", NS)
    if blip is None:
        return ""
    rid = blip.get(f"{{{NS['r']}}}embed")
    target = rels.get(rid)
    if not target or target not in media:
        return ""
    return f'<p><img src="{html.escape(media[target])}" alt=""></p>\n'


def _walk(node, rels, media):
    out = []
    for child in node:
        tag = child.tag.split("}")[-1]
        if tag == "sp":
            out.append(_shape_html(child))
        elif tag == "pic":
            out.append(_pic_html(child, rels, media))
        elif tag in ("grpSp", "graphicFrame"):
            inner = _walk(child, rels, media)
            if not inner and tag == "graphicFrame":
                txt = [_para_text(p) for p in child.iterfind(".//a:p", NS)]
                inner = "".join(f"<p>{html.escape(t)}</p>\n" for t in txt if t)
            out.append(inner)
    return "".join(out)


def _rels_for(zf, slide_name):
    rp = f"ppt/slides/_rels/{Path(slide_name).name}.rels"
    if rp not in zf.namelist():
        return {}
    root = ET.fromstring(zf.read(rp))
    rels = {}
    for rel in root:
        target = rel.get("Target", "")
        rels[rel.get("Id")] = os.path.normpath(os.path.join("ppt/slides", target)).replace("\\", "/")
    return rels


def _slide_order(zf):
    """Порядок слайдов по sldIdLst; если его нет — по номеру в имени."""
    names = [n for n in zf.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)]
    try:
        pres = ET.fromstring(zf.read("ppt/presentation.xml"))
        rels = ET.fromstring(zf.read("ppt/_rels/presentation.xml.rels"))
        by_id = {
            r.get("Id"): os.path.normpath(os.path.join("ppt", r.get("Target", ""))).replace("\\", "/")
            for r in rels
        }
        ordered = []
        for sid in pres.iterfind("./p:sldIdLst/p:sldId", NS):
            t = by_id.get(sid.get(f"{{{NS['r']}}}id"))
            if t in names:
                ordered.append(t)
        if ordered:
            return ordered
    except (KeyError, ET.ParseError):
        pass
    return sorted(names, key=lambda n: int(re.search(r"(\d+)", Path(n).stem).group(1)))


def render_pptx(src, outdir):
    media_dir = outdir / "media"
    media_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(src) as zf:
        media = {}
        for name in zf.namelist():
            if name.startswith("ppt/media/") and not name.endswith("/"):
                base = Path(name).name
                (media_dir / base).write_bytes(zf.read(name))
                media[name] = f"media/{base}"
        parts = []
        for i, slide in enumerate(_slide_order(zf), 1):
            root = ET.fromstring(zf.read(slide))
            tree = root.find(".//p:cSld/p:spTree", NS)
            body = _walk(tree, _rels_for(zf, slide), media) if tree is not None else ""
            if not body.strip():
                body = '<p class="note">Слайд без текста и растровых картинок.</p>'
            parts.append(f'<section class="slide"><span class="num">Слайд {i}</span>\n{body}</section>')
    if not parts:
        raise RenderError("в презентации не нашлось слайдов")
    return "\n".join(parts), False


def render_ppt(src, outdir):
    """Бинарный .ppt: текста от catppt может не быть, картинки — из блобов."""
    try:
        text = run([CATPPT, str(src)]).decode("utf-8", "replace").strip()
    except (RenderError, FileNotFoundError):
        text = ""
    names = extract_blobs(src.read_bytes(), outdir / "media")
    parts = [
        '<p class="note">Старый формат .ppt: разметка слайдов не читается '
        "без полноценного офиса — ниже текст и картинки из файла.</p>"
    ]
    if text:
        parts += [f"<p>{html.escape(p)}</p>" for p in text.split("\n\n") if p.strip()]
    parts.append(gallery(names, "Изображения"))
    return "\n".join(parts), False


def pick_renderer(src):
    ext = src.suffix.lower()
    if ext in PANDOC_FORMATS:
        return lambda s, o: render_pandoc(s, o, PANDOC_FORMATS[ext]), ext.lstrip(".")
    if ext == ".doc":
        return render_doc, "doc"
    if ext in SHEET_EXTS:
        return render_sheet, ext.lstrip(".")
    if ext == ".pptx":
        return render_pptx, "pptx"
    if ext == ".ppt":
        return render_ppt, "ppt"
    raise RenderError(f"не знаю, чем открыть {ext or 'файл без расширения'}")


# --------------------------------------------------------------------------
# кэш

def cache_root():
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "gdoc"


def cache_dir(src):
    st = src.stat()
    key = f"{RENDERER}|{src.resolve()}|{st.st_mtime_ns}|{st.st_size}"
    digest = hashlib.sha1(key.encode()).hexdigest()[:16]
    slug = re.sub(r"[^\w.-]+", "_", src.stem)[:48] or "doc"
    return cache_root() / f"{slug}-{digest}"


def prune_cache(keep=40):
    root = cache_root()
    if not root.is_dir():
        return
    dirs = sorted((d for d in root.iterdir() if d.is_dir()),
                  key=lambda d: d.stat().st_mtime, reverse=True)
    for stale in dirs[keep:]:
        shutil.rmtree(stale, ignore_errors=True)


def build(src, force=False):
    out = cache_dir(src)
    index = out / "index.html"
    if index.exists() and not force:
        return index
    render, kind = pick_renderer(src)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    try:
        body, wide = render(src, out)
        index.write_text(page(src.name, kind, body, wide), "utf-8")
    except Exception:
        shutil.rmtree(out, ignore_errors=True)
        raise
    prune_cache()
    return index


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="gdoc",
        description="Открыть .doc/.docx/.ppt/.pptx/.xls/.xlsx/.odt в браузере.",
    )
    ap.add_argument("files", nargs="+", metavar="ФАЙЛ")
    ap.add_argument("-f", "--force", action="store_true", help="перерисовать, игнорируя кэш")
    ap.add_argument("-p", "--path", action="store_true", help="напечатать путь, не открывать")
    ap.add_argument("-b", "--browser", default=os.environ.get("GDOC_BROWSER", "chromium"))
    ap.add_argument("--clean", action="store_true", help="очистить кэш и выйти")
    args = ap.parse_args(argv)

    if args.clean:
        shutil.rmtree(cache_root(), ignore_errors=True)
        print("кэш очищен")
        return 0

    rc = 0
    targets = []
    for name in args.files:
        src = Path(name).expanduser()
        if not src.is_file():
            print(f"gdoc: не файл: {src}", file=sys.stderr)
            rc = 1
            continue
        try:
            targets.append(build(src, args.force))
        except RenderError as exc:
            print(f"gdoc: {src.name}: {exc}", file=sys.stderr)
            rc = 1
        except Exception as exc:  # noqa: BLE001 — показать причину, а не трейс
            print(f"gdoc: {src.name}: {type(exc).__name__}: {exc}", file=sys.stderr)
            rc = 1

    if not targets:
        return rc
    if args.path:
        for t in targets:
            print(t)
        return rc

    browser = shutil.which(args.browser) or args.browser
    for t in targets:
        subprocess.Popen(
            [browser, f"--app=file://{t}"] if "chrom" in Path(browser).name
            else [browser, f"file://{t}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    return rc


if __name__ == "__main__":
    sys.exit(main())
