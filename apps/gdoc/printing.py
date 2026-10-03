"""Печать готовой страницы в PDF силами headless-chromium."""

from __future__ import annotations

import re
import shutil
import sys
import tempfile
from pathlib import Path

from common import CHROMIUM, PRINT_TIMEOUT, RenderError, run


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
