"""Кэш: имена записей, отпечаток, уборка, атомарная сборка."""

import errno
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import common
import renderers
import cache
import cli


class TestSlugify(unittest.TestCase):
    def test_keeps_cyrillic_and_replaces_separators(self):
        self.assertEqual(cache.slugify("отчёт по работе"), "отчёт_по_работе")

    def test_strips_leading_dots(self):
        self.assertFalse(cache.slugify(".hidden").startswith("."))

    def test_never_empty(self):
        self.assertEqual(cache.slugify("///"), "doc")

    def test_length_capped(self):
        self.assertLessEqual(len(cache.slugify("x" * 200)), 48)


class TestCache(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["XDG_CACHE_HOME"] = self.tmp.name
        self.doc = Path(self.tmp.name) / "a.docx"
        self.doc.write_bytes(b"hello")

    def tearDown(self):
        os.environ.pop("XDG_CACHE_HOME", None)
        self.tmp.cleanup()

    def test_stable_for_same_file(self):
        self.assertEqual(cache.cache_dir(self.doc), cache.cache_dir(self.doc))

    def test_changes_when_content_changes(self):
        before = cache.cache_dir(self.doc)
        self.doc.write_bytes(b"hello world")
        self.assertNotEqual(before, cache.cache_dir(self.doc))

    def test_fingerprint_tracks_layout(self):
        before = cache.renderer_fingerprint()
        with mock.patch.object(cache, "PAGE_CSS", cache.PAGE_CSS + "\np{}"):
            self.assertNotEqual(before, cache.renderer_fingerprint())

    def test_fingerprint_tracks_source_code(self):
        # Правка логики рендера меняет вывод так же, как правка CSS.
        before = cache.renderer_fingerprint()
        with mock.patch.object(cache, "_source_digest", lambda: "другой"):
            self.assertNotEqual(before, cache.renderer_fingerprint())

    def test_fingerprint_tracks_converter_path(self):
        before = cache.renderer_fingerprint()
        with mock.patch.object(cache, "PANDOC", "/nix/store/другой/pandoc"):
            self.assertNotEqual(before, cache.renderer_fingerprint())

    def _fill(self, count: int) -> None:
        root = cache.cache_root()
        root.mkdir(parents=True, exist_ok=True)
        for i in range(count):
            entry = root / f"doc{i:03d}-{i:016x}"
            entry.mkdir()
            os.utime(entry, (i, i))

    def test_prune_keeps_newest(self):
        self._fill(cache.CACHE_KEEP + 5)
        cache.prune_cache()
        left = [d for d in cache.cache_root().iterdir() if not d.name.startswith(".")]
        self.assertEqual(len(left), cache.CACHE_KEEP)

    def test_prune_spares_fresh_staging(self):
        self._fill(2)
        staging = cache.cache_root() / ".tmp-1-doc"
        staging.mkdir()
        cache.prune_cache()
        self.assertTrue(staging.exists())

    def test_prune_collects_abandoned_staging(self):
        # Каталог от убитого процесса иначе не удалит никто и никогда.
        self._fill(2)
        staging = cache.cache_root() / ".tmp-999999-doc"
        staging.mkdir()
        old = time.time() - cache.STAGING_MAX_AGE - 60
        os.utime(staging, (old, old))
        cache.prune_cache()
        self.assertFalse(staging.exists())

    def test_prune_spares_recently_used_entries(self):
        # Свежая запись — это та, которой кто-то прямо сейчас пользуется,
        # в том числе другой процесс.
        self._fill(cache.CACHE_KEEP + 5)
        fresh = cache.cache_root() / "doc000-0000000000000000"
        os.utime(fresh)
        cache.prune_cache()
        self.assertTrue(fresh.exists())

    def test_staging_age_cannot_outlive_a_running_process(self):
        self.assertGreater(cache.STAGING_MAX_AGE,
                           common.RUN_TIMEOUT + common.PRINT_TIMEOUT)


class TestBuild(unittest.TestCase):
    """Сборка на подставном рендерере: внешние конвертеры не нужны."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["XDG_CACHE_HOME"] = self.tmp.name
        self.doc = Path(self.tmp.name) / "файл.fake"
        self.doc.write_bytes(b"hello")
        self.calls = []

        def render(src: Path, outdir: Path) -> str:
            self.calls.append(src)
            (outdir / "media").mkdir()
            return "<p>готово</p>"

        self.fmt = renderers.Format("fake", render)
        self.patch = mock.patch.dict(renderers.FORMATS, {".fake": self.fmt})
        self.patch.start()
        self.printed = mock.patch.object(
            cache, "to_pdf",
            side_effect=lambda index, pdf: pdf.write_bytes(b"%PDF-1.4\n"))
        self.printed.start()

    def tearDown(self):
        self.printed.stop()
        self.patch.stop()
        os.environ.pop("XDG_CACHE_HOME", None)
        self.tmp.cleanup()

    def test_own_pdf_path_bypasses_the_browser(self):
        # У markdown печатает typst; подставной рендерер здесь занимает его
        # место, и chromium (его заглушка пишет %PDF-1.4) вмешаться не должен.
        def own(src: Path, workdir: Path, pdf: Path) -> None:
            pdf.write_bytes(b"%PDF-1.7\n")

        with mock.patch.dict(renderers.FORMATS,
                             {".fake": self.fmt._replace(pdf=own)}):
            out = cache.build(self.doc)
        self.assertEqual(out.read_bytes(), b"%PDF-1.7\n")
        # HTML всё равно собран: без него не работал бы --html.
        self.assertTrue((out.parent / "index.html").exists())

    def test_builds_html_and_pdf(self):
        pdf = cache.build(self.doc)
        self.assertTrue(pdf.exists())
        self.assertTrue((pdf.parent / "index.html").exists())
        self.assertEqual(pdf.name, "файл.pdf")

    def test_second_run_uses_cache(self):
        cache.build(self.doc)
        cache.build(self.doc)
        self.assertEqual(len(self.calls), 1)

    def test_force_rerenders(self):
        cache.build(self.doc)
        cache.build(self.doc, force=True)
        self.assertEqual(len(self.calls), 2)

    def test_html_only_skips_pdf(self):
        index = cache.build(self.doc, as_pdf=False)
        self.assertEqual(index.name, "index.html")
        self.assertFalse((index.parent / "файл.pdf").exists())

    def test_no_staging_left_behind(self):
        cache.build(self.doc)
        leftovers = [d.name for d in cache.cache_root().iterdir()
                     if d.name.startswith(".")]
        self.assertEqual(leftovers, [])

    def test_staging_removed_when_render_fails(self):
        with mock.patch.dict(renderers.FORMATS, {".fake": renderers.Format(
                "fake", mock.Mock(side_effect=common.RenderError("сломалось")))}):
            with self.assertRaises(common.RenderError):
                cache.build(self.doc)
        self.assertEqual(list(cache.cache_root().iterdir()), [])

    def test_loser_of_a_race_uses_the_winners_result(self):
        # Каталог уже занят другим процессом: это не ошибка.
        out = cache.cache_dir(self.doc)
        out.mkdir(parents=True)
        (out / "index.html").write_text("чужой", encoding="utf-8")
        pdf = cache.build(self.doc)
        self.assertEqual(pdf.parent, out)
        self.assertEqual((out / "index.html").read_text(encoding="utf-8"), "чужой")
        self.assertEqual(self.calls, [])

    def test_real_publish_error_is_reported(self):
        # ENOSPC/EROFS не должны маскироваться под «нас опередили».
        with mock.patch.object(Path, "replace",
                               side_effect=OSError(errno.EROFS, "Read-only file system")):
            with self.assertRaises(common.RenderError) as caught:
                cache.build(self.doc)
        self.assertIn("Read-only", str(caught.exception))

    def test_partial_cache_entry_is_rebuilt(self):
        out = cache.cache_dir(self.doc)
        out.mkdir(parents=True)
        (out / "мусор").write_text("", encoding="utf-8")
        cache.build(self.doc)
        self.assertTrue((out / "index.html").exists())

    def test_empty_pdf_is_reprinted(self):
        pdf = cache.build(self.doc)
        pdf.write_bytes(b"")
        cache.build(self.doc)
        self.assertGreater(pdf.stat().st_size, 0)

    def test_empty_file_is_refused(self):
        # Иначе часть конвертеров отдаёт чистый лист и rc=0.
        empty = Path(self.tmp.name) / "пусто.fake"
        empty.write_bytes(b"")
        with self.assertRaises(common.RenderError):
            cache.build(empty)

    def test_relative_path_reaches_renderer_as_absolute(self):
        # Конвертеры работают из каталога кэша: относительное имя
        # разрешалось бы уже от него, и документ не находился.
        was = os.getcwd()
        os.chdir(self.tmp.name)
        try:
            cli.main(["-p", self.doc.name])
        finally:
            os.chdir(was)
        self.assertEqual(self.calls, [self.doc])
        self.assertTrue(self.calls[0].is_absolute())

    def test_unknown_extension_touches_nothing(self):
        other = Path(self.tmp.name) / "x.unknown"
        other.write_bytes(b"x")
        with self.assertRaises(common.RenderError):
            cache.build(other)
        self.assertFalse(cache.cache_root().exists())
