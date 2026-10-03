"""Поиск картинок в бинарных .doc и .ppt по сигнатурам."""

import os
import tempfile
import unittest
from pathlib import Path

import blobs
from .fixtures import png, jpeg


class TestBlobParsers(unittest.TestCase):
    def test_png_end_exact(self):
        blob = png()
        self.assertEqual(blobs._png_end(b"xx" + blob + b"yy", 2), 2 + len(blob))

    def test_png_end_rejects_truncated(self):
        self.assertIsNone(blobs._png_end(png()[:-6], 0))

    def test_png_end_rejects_chunk_longer_than_rest(self):
        broken = bytearray(png())
        broken[8:12] = (1 << 30).to_bytes(4, "big")
        self.assertIsNone(blobs._png_end(bytes(broken), 0))

    def test_jpeg_end_exact(self):
        blob = jpeg()
        self.assertEqual(blobs._jpeg_end(b"zz" + blob + b"q", 2), 2 + len(blob))

    def test_jpeg_end_rejects_bad_marker(self):
        # FF D8 FF, за которым не код маркера, — случайное совпадение.
        self.assertIsNone(blobs._jpeg_end(b"\xff\xd8\xff\x00\x00\x00", 0))

    def test_jpeg_end_rejects_unterminated(self):
        self.assertIsNone(blobs._jpeg_end(jpeg()[:-2], 0))


class TestExtractBlobs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "media"

    def tearDown(self):
        self.tmp.cleanup()

    def test_finds_png_and_jpeg_in_order(self):
        data = b"junk" + png() + b"pad" + jpeg() + b"tail"
        self.assertEqual(blobs.extract_blobs(data, self.out),
                         ["media/img001.png", "media/img002.jpg"])
        self.assertTrue((self.out / "img001.png").read_bytes().startswith(b"\x89PNG"))

    def test_noise_with_fake_jpeg_signatures_yields_nothing(self):
        noise = bytearray(os.urandom(200_000))
        for pos in range(0, 200_000, 5000):
            noise[pos:pos + 3] = b"\xff\xd8\xff"
        self.assertEqual(blobs.extract_blobs(bytes(noise), self.out), [])

    def test_noise_with_fake_png_signatures_yields_nothing(self):
        noise = bytearray(os.urandom(200_000))
        for pos in range(0, 200_000, 5000):
            noise[pos:pos + 8] = b"\x89PNG\r\n\x1a\n"
        self.assertEqual(blobs.extract_blobs(bytes(noise), self.out), [])

    def test_real_image_after_fake_signature_still_found(self):
        # Ложное срабатывание не должно съедать следующую настоящую картинку.
        data = b"\xff\xd8\xff\x00" + os.urandom(500) + png()
        self.assertEqual(blobs.extract_blobs(data, self.out), ["media/img001.png"])

    def test_tiny_jpeg_ignored(self):
        self.assertEqual(blobs.extract_blobs(jpeg(64), self.out), [])

    def test_empty_input(self):
        self.assertEqual(blobs.extract_blobs(b"", self.out), [])
