"""Извлечение картинок из бинарных .doc и .ppt.

wv и catdoc не умеют распаковывать Escher-блобы, но сами картинки лежат
в файле целиком — их находим по сигнатурам и проверяем на валидность.
"""

from __future__ import annotations

import html
from pathlib import Path


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
