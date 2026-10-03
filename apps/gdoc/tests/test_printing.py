"""Печать в PDF: команда chromium и распознавание sandbox."""

import unittest
from pathlib import Path

import common
import printing


class TestSandboxDetection(unittest.TestCase):
    """Запасной путь без sandbox включается только по своей причине."""

    def test_sandbox_regex_matches_real_chromium_message(self):
        real = ("[1:1:0101/000000.000:FATAL:zygote_host_impl_linux.cc(207)] "
                "Failed to move to new namespace: PID namespaces supported, "
                "Network namespace supported, but failed: errno = Operation "
                "not permitted")
        self.assertRegex(real, printing.SANDBOX_TROUBLE)

    def test_sandbox_regex_matches_other_wordings(self):
        for line in ("No usable sandbox! Update your kernel",
                     "The SUID sandbox helper binary was found, but is not "
                     "configured correctly",
                     "clone() returned -1"):
            with self.subTest(line=line):
                self.assertRegex(line, printing.SANDBOX_TROUBLE)

    def test_sandbox_regex_ignores_unrelated_failures(self):
        for line in ("Failed to create socket",
                     "Check failed: . : Permission denied (13)"):
            with self.subTest(line=line):
                self.assertNotRegex(line, printing.SANDBOX_TROUBLE)

    def test_render_error_keeps_full_output(self):
        # Полный stderr нужен именно потому, что сообщение для человека
        # обрезано, а sandbox-строка стоит не последней.
        full = "sandbox line: No usable sandbox!\nnoise 1\nnoise 2\n"
        exc = common.RenderError("chromium: noise 1; noise 2", full)
        self.assertRegex(exc.raw, printing.SANDBOX_TROUBLE)
        self.assertNotRegex(str(exc), printing.SANDBOX_TROUBLE)


class TestChromiumCommand(unittest.TestCase):
    """Сетевая изоляция задаётся флагами — значит её надо проверять."""

    def _cmd(self):
        return printing._chromium_cmd(Path("/tmp/кэш/index.html"),
                                  Path("/tmp/кэш/out.pdf"),
                                  Path("/tmp/профиль"))

    def test_network_is_blocked(self):
        cmd = self._cmd()
        self.assertIn("--host-resolver-rules=MAP * ~NOTFOUND", cmd)
        self.assertIn("--disable-background-networking", cmd)
        self.assertIn("--disable-remote-fonts", cmd)

    def test_headless_without_header_footer(self):
        cmd = self._cmd()
        self.assertIn("--headless", cmd)
        self.assertIn("--no-pdf-header-footer", cmd)

    def test_profile_is_the_given_one(self):
        self.assertIn("--user-data-dir=/tmp/профиль", self._cmd())

    def test_page_passed_as_file_uri(self):
        # Конкатенация "file://" + путь ломается на # и % в имени каталога.
        self.assertTrue(self._cmd()[-1].startswith("file:///tmp/"))

    def test_uri_escapes_special_characters(self):
        cmd = printing._chromium_cmd(Path("/tmp/c#1/index.html"),
                                 Path("/tmp/c#1/o.pdf"), Path("/tmp/p"))
        self.assertIn("%23", cmd[-1])
        self.assertNotIn("#1/index.html", cmd[-1])

    def test_sandbox_is_not_disabled_by_default(self):
        self.assertNotIn("--no-sandbox", self._cmd())
