"""Страница, в которую заворачивается разметка."""

import unittest

import page


class TestPage(unittest.TestCase):
    def test_title_is_escaped(self):
        out = page.page("<script>x</script>", "md", "<p>тело</p>")
        self.assertNotIn("<script>x", out)

    def test_wide_switches_to_landscape(self):
        self.assertIn("A4 landscape", page.page("t", "xlsx", "", wide=True))
        self.assertNotIn("landscape", page.page("t", "docx", ""))

    def test_own_script_is_present(self):
        self.assertIn("fitMath", page.page("t", "md", "<p>x</p>"))
