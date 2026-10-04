"""Разбор командной строки и запуск просмотрщика."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable

from cache import build, cache_root
from common import RenderError
from renderers import VIEWER_READS


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
        description="Открыть .doc/.docx/.ppt/.pptx/.xls/.xlsx/.odt/.md в zathura. "
                    "PDF, epub, djvu и прочее готовое открывается как есть.",
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
        if src.suffix.lower() in VIEWER_READS:
            if args.out or args.html:
                fail(f"{src.name}: это уже готовый для просмотра формат, "
                     f"рендерить нечего")
                rc = 1
                continue
            ready.append((src, src))
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
