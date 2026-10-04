"""Командная строка: аргументы, -o, определение каталога."""

import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path

import common
import cli


class TestLooksLikeDir(unittest.TestCase):
    def test_trailing_slash(self):
        self.assertTrue(cli.looks_like_dir("/tmp/нет-такого/"))

    def test_plain_name_is_not_a_dir(self):
        self.assertFalse(cli.looks_like_dir("/tmp/нет-такого"))

    def test_existing_directory(self):
        self.assertTrue(cli.looks_like_dir(tempfile.gettempdir()))


class TestArgs(unittest.TestCase):
    def _fails(self, argv):
        with self.assertRaises(SystemExit):
            cli.parse_args(argv)

    def test_clean_needs_no_files(self):
        _, args = cli.parse_args(["--clean"])
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

    def test_many_files_accept_trailing_slash(self):
        _, args = cli.parse_args(["--out", "/nope/dir/", "a.docx", "b.docx"])
        self.assertEqual(args.out, "/nope/dir/")

    def test_force_and_overwrite_are_separate(self):
        _, args = cli.parse_args(["-f", "a.docx"])
        self.assertTrue(args.force)
        self.assertFalse(args.overwrite)


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
        self.assertEqual(cli.export(self.pdf, self.src, str(dest), False),
                         dest / "отчёт за год.pdf")

    def test_trailing_slash_creates_directory(self):
        # Именно строкой: Path срезал бы слэш, и намерение «это каталог»
        # потерялось бы ещё до вызова.
        final = cli.export(self.pdf, self.src,
                            str(self.root / "new") + os.sep, False)
        self.assertEqual(final.parent.name, "new")
        self.assertEqual(final.name, "отчёт за год.pdf")
        self.assertTrue(final.exists())

    def test_extension_appended(self):
        final = cli.export(self.pdf, self.src, str(self.root / "название"), False)
        self.assertEqual(final.name, "название.pdf")

    def test_refuses_to_overwrite(self):
        target = self.root / "busy.pdf"
        target.write_bytes("важное".encode())
        with self.assertRaises(common.RenderError):
            cli.export(self.pdf, self.src, str(target), False)
        self.assertEqual(target.read_bytes(), "важное".encode())

    def test_overwrite_replaces(self):
        target = self.root / "busy.pdf"
        target.write_bytes("важное".encode())
        cli.export(self.pdf, self.src, str(target), True)
        self.assertEqual(target.read_bytes(), b"%PDF-1.4\n")


class TestViewerFormats(unittest.TestCase):
    """PDF, epub и прочее готовое отдаются как есть, мимо кэша."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.book = Path(self.tmp.name) / "книга.epub"
        self.book.write_bytes(b"PK\x03\x04")

    def tearDown(self):
        self.tmp.cleanup()

    def _run(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = cli.main(argv)
        return rc, out.getvalue(), err.getvalue()

    def test_path_is_the_source_itself(self):
        rc, out, _ = self._run(["-p", str(self.book)])
        self.assertEqual(rc, 0)
        self.assertEqual(out.strip(), str(self.book))

    def test_nothing_lands_in_the_cache(self):
        with tempfile.TemporaryDirectory() as cache_home:
            os.environ["XDG_CACHE_HOME"] = cache_home
            try:
                self._run(["-p", str(self.book)])
                self.assertFalse((Path(cache_home) / "gdoc").exists())
            finally:
                os.environ.pop("XDG_CACHE_HOME", None)

    def test_out_is_refused(self):
        # Просили сохранить PDF, а PDF никто не делал: молча скопировать
        # epub под именем .pdf было бы хуже отказа.
        rc, _, err = self._run(["-o", self.tmp.name, str(self.book)])
        self.assertEqual(rc, 1)
        self.assertIn("рендерить нечего", err)

    def test_html_is_refused(self):
        rc, _, err = self._run(["--html", str(self.book)])
        self.assertEqual(rc, 1)
        self.assertIn("рендерить нечего", err)
