#!/usr/bin/env python3
"""Тесты чистых функций gdoc: парсеры, очистка HTML, кэш.

Запуск: python3 -m unittest discover -s home-manager/gdoc

Здесь только то, что работает без внешних конвертеров, — сборку настоящих
документов проверять нечем без pandoc и gnumeric под рукой.
"""

import os
import tempfile
import unittest
import zlib
from pathlib import Path

import gdoc


class TestSanitize(unittest.TestCase):
    def test_script_removed_with_content(self):
        out = gdoc.sanitize('<p>до</p><script>alert(1)</script><p>после</p>')
        self.assertNotIn("alert", out)
        self.assertNotIn("<script", out)
        self.assertIn("до", out)
        self.assertIn("после", out)

    def test_event_handlers_removed(self):
        out = gdoc.sanitize('<img src="a.png" onerror="fetch(1)" alt="x">')
        self.assertNotIn("onerror", out)
        self.assertIn('src="a.png"', out)

    def test_external_and_scheme_urls_dropped(self):
        for url in ("http://evil/x.png", "https://evil/x.png",
                    "//evil/x.png", "file:///etc/passwd",
                    "javascript:alert(1)", "data:text/html,<b>"):
            with self.subTest(url=url):
                out = gdoc.sanitize(f'<img src="{url}">')
                self.assertNotIn("evil", out)
                self.assertNotIn("javascript", out)
                self.assertNotIn("passwd", out)

    def test_relative_and_data_image_kept(self):
        out = gdoc.sanitize('<img src="media/img001.png">')
        self.assertIn('src="media/img001.png"', out)
        out = gdoc.sanitize('<img src="data:image/png;base64,AAA">')
        self.assertIn("data:image/png", out)

    def test_iframe_and_object_removed(self):
        out = gdoc.sanitize('<iframe src="file:///etc/passwd"></iframe>'
                            '<object data="x"></object>')
        self.assertNotIn("iframe", out)
        self.assertNotIn("object", out)

    def test_unbalanced_tags_closed(self):
        out = gdoc.sanitize("<div><p>текст")
        self.assertEqual(out.count("</p>"), 1)
        self.assertEqual(out.count("</div>"), 1)

    def test_stray_close_tag_ignored(self):
        self.assertEqual(gdoc.sanitize("текст</div>"), "текст")

    def test_style_with_url_dropped_but_colors_kept(self):
        out = gdoc.sanitize('<p style="background:url(http://evil/x)">a</p>')
        self.assertNotIn("evil", out)
        out = gdoc.sanitize('<p style="color: Black">a</p>')
        self.assertIn("color: Black", out)

    def test_mathml_survives(self):
        src = ('<math display="block"><mfrac><mi>a</mi><mn>2</mn></mfrac></math>')
        out = gdoc.sanitize(src)
        self.assertIn("<math", out)
        self.assertIn("<mfrac>", out)
        self.assertIn('display="block"', out)

    def test_text_is_escaped(self):
        self.assertIn("&lt;", gdoc.sanitize("a &lt; b"))
        self.assertNotIn("<b>", gdoc.sanitize("5 &lt; 6 &amp; 7"))

    def test_head_dropped_body_kept(self):
        out = gdoc.sanitize(
            "<html><head><title>T</title><style>p{}</style></head>"
            "<body><p>тело</p></body></html>")
        self.assertNotIn("T", out)
        self.assertNotIn("p{}", out)
        self.assertIn("<p>тело</p>", out)


def _png(payload: bytes = b"\x00" * 16) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (len(data).to_bytes(4, "big") + kind + data
                + zlib.crc32(kind + data).to_bytes(4, "big"))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", b"\x00" * 13)
            + chunk(b"IDAT", payload)
            + chunk(b"IEND", b""))


def _jpeg(size: int = 4096) -> bytes:
    body = b"\xff\xfe" + (size).to_bytes(2, "big") + b"\x00" * (size - 2)
    return b"\xff\xd8\xff" + body[1:] + b"\xff\xd9"


class TestExtractBlobs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "media"

    def tearDown(self):
        self.tmp.cleanup()

    def test_finds_png_and_jpeg_in_order(self):
        data = b"junk" + _png() + b"pad" + _jpeg() + b"tail"
        names = gdoc.extract_blobs(data, self.out)
        self.assertEqual(names, ["media/img001.png", "media/img002.jpg"])
        self.assertTrue((self.out / "img001.png").read_bytes().startswith(b"\x89PNG"))

    def test_random_noise_yields_nothing(self):
        # Шум с посеянными сигнатурами не должен превращаться в картинки:
        # один ложный блоб сдвигает все остальные в документе.
        noise = bytearray(os.urandom(200_000))
        for pos in range(0, 200_000, 5000):
            noise[pos:pos + 3] = b"\xff\xd8\xff"
        self.assertEqual(gdoc.extract_blobs(bytes(noise), self.out), [])

    def test_truncated_png_ignored(self):
        broken = _png()[:-6]
        self.assertEqual(gdoc.extract_blobs(b"x" + broken, self.out), [])

    def test_tiny_jpeg_ignored(self):
        self.assertEqual(gdoc.extract_blobs(_jpeg(64), self.out), [])

    def test_empty_input(self):
        self.assertEqual(gdoc.extract_blobs(b"", self.out), [])


class TestIsNumber(unittest.TestCase):
    def test_numbers(self):
        for value in ("1", "-5", "3.14", "3,14", "61", "99%", "1 000", "-0,5", "-,5", "1 234 567"):
            self.assertTrue(gdoc.is_number(value), value)

    def test_not_numbers(self):
        for value in ("", "  ", "Итого", "12.05.2024", "0.0.1",
                      "1 2 3", "FreeCad", "#DIV/0!"):
            self.assertFalse(gdoc.is_number(value), value)


class TestTable(unittest.TestCase):
    def test_trailing_empty_columns_and_rows_dropped(self):
        rows = [["a", "1", "", ""], ["b", "2", "", ""], ["", "", "", ""]]
        out = gdoc._table(rows, "Лист")
        self.assertEqual(out.count("<tr>"), 2)
        self.assertEqual(out.count("<td"), 4)

    def test_numbers_get_class(self):
        out = gdoc._table([["Итого", "61"]], "Л")
        self.assertIn('<td class="n">61</td>', out)
        self.assertIn("<td>Итого</td>", out)

    def test_row_limit_reported(self):
        rows = [[str(i)] for i in range(gdoc.MAX_ROWS + 10)]
        out = gdoc._table(rows, "Л")
        self.assertIn("Показаны первые", out)
        self.assertEqual(out.count("<tr>"), gdoc.MAX_ROWS)

    def test_empty_sheet(self):
        self.assertIn("Лист пустой", gdoc._table([["", ""]], "Л"))

    def test_cell_content_escaped(self):
        out = gdoc._table([["<script>"]], "Л")
        self.assertNotIn("<script>", out)


class TestSlugify(unittest.TestCase):
    def test_keeps_cyrillic_and_replaces_separators(self):
        self.assertEqual(gdoc.slugify("отчёт по работе"), "отчёт_по_работе")

    def test_strips_leading_dots(self):
        self.assertFalse(gdoc.slugify(".hidden").startswith("."))

    def test_never_empty(self):
        self.assertEqual(gdoc.slugify("///"), "doc")

    def test_length_capped(self):
        self.assertLessEqual(len(gdoc.slugify("x" * 200)), 48)


class TestCacheKey(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["XDG_CACHE_HOME"] = self.tmp.name
        self.doc = Path(self.tmp.name) / "a.docx"
        self.doc.write_bytes(b"hello")

    def tearDown(self):
        os.environ.pop("XDG_CACHE_HOME", None)
        self.tmp.cleanup()

    def test_stable_for_same_file(self):
        self.assertEqual(gdoc.cache_dir(self.doc), gdoc.cache_dir(self.doc))

    def test_changes_when_content_changes(self):
        before = gdoc.cache_dir(self.doc)
        self.doc.write_bytes(b"hello world")
        self.assertNotEqual(before, gdoc.cache_dir(self.doc))

    def test_fingerprint_tracks_layout(self):
        before = gdoc.renderer_fingerprint()
        original = gdoc.PAGE_CSS
        try:
            gdoc.PAGE_CSS = original + "\np{}"
            self.assertNotEqual(before, gdoc.renderer_fingerprint())
        finally:
            gdoc.PAGE_CSS = original

    def test_prune_keeps_newest_and_skips_dot_dirs(self):
        root = gdoc.cache_root()
        root.mkdir(parents=True, exist_ok=True)
        for i in range(gdoc.CACHE_KEEP + 5):
            entry = root / f"doc{i:03d}-{i:016x}"
            entry.mkdir()
            os.utime(entry, (i, i))
        staging = root / ".tmp-1-doc"
        staging.mkdir()
        gdoc.prune_cache()
        left = [d for d in root.iterdir() if not d.name.startswith(".")]
        self.assertEqual(len(left), gdoc.CACHE_KEEP)
        self.assertTrue(staging.exists())


class TestArgs(unittest.TestCase):
    def _fails(self, argv):
        with self.assertRaises(SystemExit):
            gdoc.parse_args(argv)

    def test_clean_needs_no_files(self):
        _, args = gdoc.parse_args(["--clean"])
        self.assertTrue(args.clean)

    def test_files_required_otherwise(self):
        self._fails([])

    def test_out_conflicts(self):
        self._fails(["--out", ".", "--html", "a.docx"])
        self._fails(["--out", ".", "--path", "a.docx"])

    def test_clean_rejects_files(self):
        self._fails(["--clean", "a.docx"])

    def test_many_files_need_directory(self):
        self._fails(["--out", "/nope/one.pdf", "a.docx", "b.docx"])


class TestExport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.pdf = self.root / "built.pdf"
        self.pdf.write_bytes(b"%PDF-1.4\n")
        self.src = self.root / "отчёт за год.docx"
        self.src.write_bytes(b"x")

    def tearDown(self):
        self.tmp.cleanup()

    def test_directory_keeps_original_name(self):
        dest = self.root / "out"
        dest.mkdir()
        self.assertEqual(gdoc.export(self.pdf, self.src, str(dest), False),
                         dest / "отчёт за год.pdf")

    def test_trailing_slash_creates_directory(self):
        # Именно строкой: Path срезал бы слэш, и намерение «это каталог»
        # потерялось бы ещё до вызова.
        dest = str(self.root / "new") + os.sep
        final = gdoc.export(self.pdf, self.src, dest, False)
        self.assertEqual(final.parent.name, "new")
        self.assertEqual(final.name, "отчёт за год.pdf")
        self.assertTrue(final.exists())

    def test_extension_appended(self):
        final = gdoc.export(self.pdf, self.src, str(self.root / "название"), False)
        self.assertEqual(final.name, "название.pdf")

    def test_refuses_to_overwrite(self):
        target = self.root / "busy.pdf"
        target.write_bytes("важное".encode())
        with self.assertRaises(gdoc.RenderError):
            gdoc.export(self.pdf, self.src, str(target), False)
        self.assertEqual(target.read_bytes(), "важное".encode())

    def test_force_overwrites(self):
        target = self.root / "busy.pdf"
        target.write_bytes("важное".encode())
        gdoc.export(self.pdf, self.src, str(target), True)
        self.assertEqual(target.read_bytes(), b"%PDF-1.4\n")


class TestPickFormat(unittest.TestCase):
    def test_case_insensitive(self):
        self.assertEqual(gdoc.pick_format(Path("A.DOCX")).kind, "docx")

    def test_sheets_are_wide(self):
        self.assertTrue(gdoc.pick_format(Path("a.xlsx")).wide)
        self.assertFalse(gdoc.pick_format(Path("a.docx")).wide)

    def test_unknown_extension(self):
        with self.assertRaises(gdoc.RenderError):
            gdoc.pick_format(Path("a.tex"))
        with self.assertRaises(gdoc.RenderError):
            gdoc.pick_format(Path("noext"))


if __name__ == "__main__":
    unittest.main()
