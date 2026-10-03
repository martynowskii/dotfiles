"""Страница, в которую заворачивается разметка документа."""

from __future__ import annotations

import html


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
