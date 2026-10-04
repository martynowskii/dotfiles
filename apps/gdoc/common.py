"""Запуск конвертеров и общие для всех модулей мелочи."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


# Конвертеры иногда зависают на битом вводе. Из .desktop такой процесс уходит
# в фон навсегда, поэтому у каждого запуска есть потолок.
RUN_TIMEOUT = 300


PRINT_TIMEOUT = 180


def tool(env_var: str, name: str) -> str:
    """Путь до утилиты: из окружения (его задаёт nix-обёртка) либо из PATH."""
    return os.environ.get(env_var) or shutil.which(name) or name


PANDOC = tool("GDOC_PANDOC", "pandoc")
WVHTML = tool("GDOC_WVHTML", "wvHtml")
SSCONVERT = tool("GDOC_SSCONVERT", "ssconvert")
CATPPT = tool("GDOC_CATPPT", "catppt")
ANTIWORD = tool("GDOC_ANTIWORD", "antiword")
CHROMIUM = tool("GDOC_CHROMIUM", "chromium")
TYPST = tool("GDOC_TYPST", "typst")

# Каталог со шрифтами для typst. Пусто — брать системные; nix-обёртка его
# всегда задаёт, чтобы одна и та же разметка печаталась одинаково везде.
TYPST_FONTS = os.environ.get("GDOC_TYPST_FONTS", "")


class RenderError(Exception):
    """Ошибка, которую можно показать пользователю одной строкой.

    В `raw` лежит полный вывод программы: сообщение для человека урезано до
    пары строк, а разбирать причину иногда нужно по всему тексту.
    """

    def __init__(self, message: str, raw: str = "") -> None:
        super().__init__(message)
        self.raw = raw


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
