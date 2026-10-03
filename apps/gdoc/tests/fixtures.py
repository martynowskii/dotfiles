"""Синтетические картинки: тесты не должны тянуть внешние файлы."""

import zlib


def png(payload: bytes = b"\x00" * 16) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (len(data).to_bytes(4, "big") + kind + data
                + zlib.crc32(kind + data).to_bytes(4, "big"))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", b"\x00" * 13)
            + chunk(b"IDAT", payload) + chunk(b"IEND", b""))


def jpeg(size: int = 4096) -> bytes:
    comment = b"\xff\xfe" + size.to_bytes(2, "big") + b"\x00" * (size - 2)
    return b"\xff\xd8" + comment + b"\xff\xd9"
