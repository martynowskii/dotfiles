"""Разбор вывода конвертеров."""

import unittest

import common


class TestWhy(unittest.TestCase):
    """Из шума конвертера надо достать настоящую причину."""

    def test_why_keeps_last_meaningful_lines(self):
        out = common._why(b"first\nsecond\nthird\n", 1)
        self.assertIn("third", out)
        self.assertNotIn("first", out)

    def test_why_drops_environment_noise(self):
        out = common._why("dconf-CRITICAL: ...\nнастоящая причина\n".encode(), 1)
        self.assertEqual(out, "настоящая причина")

    def test_why_drops_ghc_internals(self):
        noisy = (b"pandoc: real reason\n"
                 b"  called at libraries/ghc-internal/src/GHC/IO.hs:319:20\n")
        self.assertIn("real reason", common._why(noisy, 1))
        self.assertNotIn("ghc-internal", common._why(noisy, 1))

    def test_why_falls_back_to_code(self):
        self.assertEqual(common._why(b"", 3), "код 3")
