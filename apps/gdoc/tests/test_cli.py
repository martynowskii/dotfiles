"""Командная строка: аргументы, -o, определение каталога."""

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
