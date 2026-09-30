#!/usr/bin/env python3
"""Тесты gdoc: очистка HTML, парсеры, кэш, сборка.

Запуск: cd home-manager/gdoc && python3 -m unittest test_gdoc

Внешние конвертеры не нужны: pptx читается своим кодом через zipfile, а
сборка проверяется на подставном рендерере.
"""

import errno
import io
import os
import tempfile
import time
import unittest
import zipfile
import zlib
from pathlib import Path
from unittest import mock

import gdoc


def clean(markup: str) -> str:
    """Очищенная разметка без счётчика потерь."""
    return gdoc.sanitize(markup)[0]


class TestSanitizeActiveContent(unittest.TestCase):
    def test_script_removed_with_content(self):
        out = clean('<p>до</p><script>alert(1)</script><p>после</p>')
        self.assertNotIn("alert", out)
        self.assertNotIn("<script", out)
        self.assertIn("до", out)
        self.assertIn("после", out)

    def test_event_handlers_removed_any_case(self):
        for attr in ("onerror", "OnError", "ONLOAD", "onclick"):
            with self.subTest(attr=attr):
                out = clean(f'<img src="a.png" {attr}="fetch(1)">')
                self.assertNotIn("fetch", out.lower())

    def test_iframe_object_embed_removed(self):
        out = clean('<iframe src="x"></iframe><object data="x"></object>'
                    '<embed src="x"><applet code="x"></applet>')
        for tag in ("iframe", "object", "applet"):
            self.assertNotIn(tag, out)

    def test_nested_template_fully_dropped(self):
        out = clean("<template><template><p>внутри</p></template>"
                    "<b>тоже</b></template><i>снаружи</i>")
        self.assertNotIn("внутри", out)
        self.assertNotIn("тоже", out)
        self.assertIn("снаружи", out)

    def test_srcdoc_and_meta_refresh_dropped(self):
        out = clean('<iframe srcdoc="<script>x</script>"></iframe>')
        self.assertNotIn("script", out)
        out = clean('<meta http-equiv="refresh" content="0;url=http://evil/">')
        self.assertNotIn("evil", out)

    def test_smil_animation_dropped(self):
        # <animate> подставляет адрес в href уже после очистки, и он лежит
        # в values/to/from — не в атрибутах ссылок.
        out = clean('<svg><image href="x"><animate attributeName="href" '
                    'to="http://evil/s1" begin="0s"/></image></svg>')
        self.assertNotIn("evil", out)
        self.assertNotIn("animate", out)
        out = clean('<svg><set attributeName="href" to="http://evil/s2"/></svg>')
        self.assertNotIn("evil", out)

    def test_svg_data_uri_dropped_raster_kept(self):
        # data:image/svg+xml — документ, он умеет нести скрипты.
        out = clean('<img src="data:image/svg+xml;base64,PHN2Zz4=">')
        self.assertNotIn("svg+xml", out)
        self.assertIn("data:image/png", clean('<img src="data:image/png;base64,AAA">'))

    def test_svg_and_math_hrefs_filtered(self):
        out = clean('<svg><a xlink:href="javascript:alert(1)"><text>x</text></a></svg>')
        self.assertNotIn("javascript", out)
        out = clean('<math href="http://evil/x"><mi>a</mi></math>')
        self.assertNotIn("evil", out)


class TestSanitizeUrls(unittest.TestCase):
    def test_scheme_urls_dropped(self):
        for url in ("http://evil/x.png", "https://evil/x.png", "//evil/x.png",
                    "file:///etc/passwd", "javascript:alert(1)",
                    "JaVaScRiPt:alert(1)", "data:text/html,<b>"):
            with self.subTest(url=url):
                out = clean(f'<img src="{url}">')
                self.assertNotIn("evil", out)
                self.assertNotIn("passwd", out)
                self.assertNotIn("alert", out)

    def test_absolute_local_path_dropped(self):
        # Страница живёт по file://, так что такой src читается с диска.
        out = clean('<img src="/etc/hostname">')
        self.assertNotIn("hostname", out)

    def test_parent_traversal_dropped(self):
        out = clean('<img src="../../../../etc/hostname">')
        self.assertNotIn("hostname", out)
        out = clean('<img src="media/../../secret.png">')
        self.assertNotIn("secret", out)

    def test_relative_and_data_image_kept(self):
        self.assertIn('src="media/img001.png"', clean('<img src="media/img001.png">'))
        self.assertIn("data:image/png", clean('<img src="data:image/png;base64,AAA">'))

    def test_anchor_kept(self):
        self.assertIn('href="#sec"', clean('<a href="#sec">к разделу</a>'))

    def test_dropped_resources_are_counted(self):
        _, dropped = gdoc.sanitize('<img src="http://a/1"><img src="/etc/x">')
        self.assertEqual(sum(dropped.values()), 2)

    def test_note_added_when_something_dropped(self):
        body = gdoc.sanitized_body('<img src="http://evil/x">')
        self.assertIn("Вырезано", body)
        self.assertIn("ссылок на внешние ресурсы: 1", body)

    def test_note_mentions_every_kind_of_loss(self):
        body = gdoc.sanitized_body(
            '<img src="http://evil/x">'
            '<iframe src="http://evil/y"></iframe>'
            '<p style="background:url(http://evil/z)">t</p>')
        self.assertIn("ссылок на внешние ресурсы", body)
        self.assertIn("внешних вставок", body)
        self.assertIn("правил оформления", body)

    def test_no_note_when_nothing_dropped(self):
        self.assertNotIn("Вырезано", gdoc.sanitized_body("<p>чисто</p>"))


class TestSanitizeStyle(unittest.TestCase):
    def test_plain_url_dropped(self):
        self.assertNotIn("evil", clean('<p style="background:url(http://evil/x)">a</p>'))

    def test_css_escape_does_not_bypass(self):
        # Денилист по подстроке "url(" такое пропускал, а CSS это понимает.
        out = clean(r'<p style="background:u\72l(http://evil/x)">a</p>')
        self.assertNotIn("evil", out)
        self.assertNotIn(r"\72", out)

    def test_import_and_expression_dropped(self):
        self.assertNotIn("evil", clean('<p style="@import url(http://evil/)">a</p>'))
        self.assertNotIn("expression", clean('<p style="width:expression(1)">a</p>'))

    def test_plain_properties_kept(self):
        out = clean('<p style="color: Black; background-color: White">a</p>')
        self.assertIn("color: Black", out)
        self.assertIn("background-color: White", out)

    def test_color_functions_kept(self):
        # rgb() — основная форма записи цвета у офисных конвертеров.
        for value in ("color: rgb(200,0,0)", "color: rgba(0,0,0,.5)",
                      "background-color: hsl(10,5%,5%)",
                      "border: 1px solid rgb(0,0,0)"):
            with self.subTest(value=value):
                self.assertIn("style=", clean(f'<p style="{value}">t</p>'))

    def test_page_breaks_kept(self):
        self.assertIn("page-break-inside",
                      clean('<p style="page-break-inside: avoid">t</p>'))

    def test_dropped_style_is_counted(self):
        _, dropped = gdoc.sanitize('<p style="background:url(http://evil/x)">t</p>')
        self.assertEqual(sum(dropped.values()), 1)

    def test_unknown_property_dropped(self):
        self.assertNotIn("behavior", clean('<p style="behavior: url(x.htc)">a</p>'))


class TestSanitizeStructure(unittest.TestCase):
    def test_unbalanced_tags_closed(self):
        out = clean("<div><p>текст")
        self.assertEqual(out.count("</p>"), 1)
        self.assertEqual(out.count("</div>"), 1)

    def test_stray_close_tag_ignored(self):
        self.assertEqual(clean("текст</div>"), "текст")

    def test_self_closed_non_void_is_balanced(self):
        # В HTML `/` перед `>` игнорируется, поэтому <section/> открыл бы
        # элемент и проглотил весь остаток документа.
        out = clean("<section/>после")
        self.assertEqual(out, "<section></section>после")

    def test_self_closed_void_stays_void(self):
        self.assertEqual(clean("<br/>"), "<br>")
        self.assertNotIn("</br>", clean("<br/>"))

    def test_deep_nesting_is_bounded(self):
        depth = gdoc.MAX_DEPTH * 20
        out = clean("<div>" * depth + "дно" + "</div>" * depth)
        self.assertIn("дно", out)
        self.assertLessEqual(out.count("<div>"), gdoc.MAX_DEPTH)

    def test_deep_nesting_is_fast(self):
        started = time.monotonic()
        clean("<div>" * 20000 + "x" + "</div>" * 20000)
        self.assertLess(time.monotonic() - started, 2.0)

    def test_depth_overflow_is_reported(self):
        deep = "<div>" * (gdoc.MAX_DEPTH + 5) + "дно"
        body = gdoc.sanitized_body(deep)
        self.assertIn("уровней вложенности", body)

    def test_weird_tag_name_dropped(self):
        out = clean('<a"onload=x">t</a"onload=x">')
        self.assertNotIn("onload", out)
        self.assertIn("t", out)

    def test_mathml_survives(self):
        out = clean('<math display="block"><mfrac><mi>a</mi><mn>2</mn></mfrac></math>')
        self.assertIn("<math", out)
        self.assertIn("<mfrac>", out)
        self.assertIn('display="block"', out)

    def test_text_is_escaped(self):
        self.assertIn("&lt;", clean("a &lt; b"))
        self.assertNotIn("<b>", clean("5 &lt; 6 &amp; 7"))

    def test_content_survives_tags_without_a_closing_form(self):
        # У <embed> и <frame> закрывающего тега не бывает, поэтому удаление
        # «вместе с содержимым» съедало весь остаток документа.
        for markup in ('<p>до</p><embed src="x"><p>ПОСЛЕ</p>',
                       '<p>до</p><frame src="x"><p>ПОСЛЕ</p>',
                       '<svg><animate attributeName="href" to="http://evil/">'
                       '</svg><p>ПОСЛЕ</p>',
                       '<svg><set attributeName="href" to="http://evil/"></svg>'
                       '<p>ПОСЛЕ</p>'):
            with self.subTest(markup=markup):
                out = clean(markup)
                self.assertIn("ПОСЛЕ", out)
                self.assertNotIn("evil", out)

    def test_single_tags_are_not_suppressors(self):
        # Инвариант: тег без закрывающей формы нельзя класть в DROP_TREE,
        # снять подавление будет некому.
        self.assertEqual(
            gdoc._Sanitizer.VOID & gdoc._Sanitizer.DROP_TREE, frozenset())
        self.assertEqual(
            gdoc._Sanitizer.DROP_SELF & gdoc._Sanitizer.DROP_TREE, frozenset())

    def test_dropped_embed_is_counted(self):
        _, dropped = gdoc.sanitize('<embed src="http://evil/x">')
        self.assertEqual(sum(dropped.values()), 1)

    def test_head_dropped_body_kept(self):
        out = clean("<html><head><title>T</title><style>p{}</style></head>"
                    "<body><p>тело</p></body></html>")
        self.assertNotIn("T", out)
        self.assertNotIn("p{}", out)
        self.assertIn("<p>тело</p>", out)


class TestWhyAndSandbox(unittest.TestCase):
    def test_why_keeps_last_meaningful_lines(self):
        out = gdoc._why(b"first\nsecond\nthird\n", 1)
        self.assertIn("third", out)
        self.assertNotIn("first", out)

    def test_why_drops_environment_noise(self):
        out = gdoc._why("dconf-CRITICAL: ...\nнастоящая причина\n".encode(), 1)
        self.assertEqual(out, "настоящая причина")

    def test_why_drops_ghc_internals(self):
        noisy = (b"pandoc: real reason\n"
                 b"  called at libraries/ghc-internal/src/GHC/IO.hs:319:20\n")
        self.assertIn("real reason", gdoc._why(noisy, 1))
        self.assertNotIn("ghc-internal", gdoc._why(noisy, 1))

    def test_why_falls_back_to_code(self):
        self.assertEqual(gdoc._why(b"", 3), "код 3")

    def test_sandbox_regex_matches_real_chromium_message(self):
        real = ("[1:1:0101/000000.000:FATAL:zygote_host_impl_linux.cc(207)] "
                "Failed to move to new namespace: PID namespaces supported, "
                "Network namespace supported, but failed: errno = Operation "
                "not permitted")
        self.assertRegex(real, gdoc.SANDBOX_TROUBLE)

    def test_sandbox_regex_matches_other_wordings(self):
        for line in ("No usable sandbox! Update your kernel",
                     "The SUID sandbox helper binary was found, but is not "
                     "configured correctly",
                     "clone() returned -1"):
            with self.subTest(line=line):
                self.assertRegex(line, gdoc.SANDBOX_TROUBLE)

    def test_sandbox_regex_ignores_unrelated_failures(self):
        for line in ("Failed to create socket",
                     "Check failed: . : Permission denied (13)"):
            with self.subTest(line=line):
                self.assertNotRegex(line, gdoc.SANDBOX_TROUBLE)

    def test_render_error_keeps_full_output(self):
        # Полный stderr нужен именно потому, что сообщение для человека
        # обрезано, а sandbox-строка стоит не последней.
        full = "sandbox line: No usable sandbox!\nnoise 1\nnoise 2\n"
        exc = gdoc.RenderError("chromium: noise 1; noise 2", full)
        self.assertRegex(exc.raw, gdoc.SANDBOX_TROUBLE)
        self.assertNotRegex(str(exc), gdoc.SANDBOX_TROUBLE)


def _png(payload: bytes = b"\x00" * 16) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (len(data).to_bytes(4, "big") + kind + data
                + zlib.crc32(kind + data).to_bytes(4, "big"))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", b"\x00" * 13)
            + chunk(b"IDAT", payload) + chunk(b"IEND", b""))


def _jpeg(size: int = 4096) -> bytes:
    comment = b"\xff\xfe" + size.to_bytes(2, "big") + b"\x00" * (size - 2)
    return b"\xff\xd8" + comment + b"\xff\xd9"


class TestBlobParsers(unittest.TestCase):
    def test_png_end_exact(self):
        blob = _png()
        self.assertEqual(gdoc._png_end(b"xx" + blob + b"yy", 2), 2 + len(blob))

    def test_png_end_rejects_truncated(self):
        self.assertIsNone(gdoc._png_end(_png()[:-6], 0))

    def test_png_end_rejects_chunk_longer_than_rest(self):
        broken = bytearray(_png())
        broken[8:12] = (1 << 30).to_bytes(4, "big")
        self.assertIsNone(gdoc._png_end(bytes(broken), 0))

    def test_jpeg_end_exact(self):
        blob = _jpeg()
        self.assertEqual(gdoc._jpeg_end(b"zz" + blob + b"q", 2), 2 + len(blob))

    def test_jpeg_end_rejects_bad_marker(self):
        # FF D8 FF, за которым не код маркера, — случайное совпадение.
        self.assertIsNone(gdoc._jpeg_end(b"\xff\xd8\xff\x00\x00\x00", 0))

    def test_jpeg_end_rejects_unterminated(self):
        self.assertIsNone(gdoc._jpeg_end(_jpeg()[:-2], 0))


class TestExtractBlobs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "media"

    def tearDown(self):
        self.tmp.cleanup()

    def test_finds_png_and_jpeg_in_order(self):
        data = b"junk" + _png() + b"pad" + _jpeg() + b"tail"
        self.assertEqual(gdoc.extract_blobs(data, self.out),
                         ["media/img001.png", "media/img002.jpg"])
        self.assertTrue((self.out / "img001.png").read_bytes().startswith(b"\x89PNG"))

    def test_noise_with_fake_jpeg_signatures_yields_nothing(self):
        noise = bytearray(os.urandom(200_000))
        for pos in range(0, 200_000, 5000):
            noise[pos:pos + 3] = b"\xff\xd8\xff"
        self.assertEqual(gdoc.extract_blobs(bytes(noise), self.out), [])

    def test_noise_with_fake_png_signatures_yields_nothing(self):
        noise = bytearray(os.urandom(200_000))
        for pos in range(0, 200_000, 5000):
            noise[pos:pos + 8] = b"\x89PNG\r\n\x1a\n"
        self.assertEqual(gdoc.extract_blobs(bytes(noise), self.out), [])

    def test_real_image_after_fake_signature_still_found(self):
        # Ложное срабатывание не должно съедать следующую настоящую картинку.
        data = b"\xff\xd8\xff\x00" + os.urandom(500) + _png()
        self.assertEqual(gdoc.extract_blobs(data, self.out), ["media/img001.png"])

    def test_tiny_jpeg_ignored(self):
        self.assertEqual(gdoc.extract_blobs(_jpeg(64), self.out), [])

    def test_empty_input(self):
        self.assertEqual(gdoc.extract_blobs(b"", self.out), [])


class TestIsNumber(unittest.TestCase):
    def test_numbers(self):
        for value in ("1", "-5", "+5", "3.14", "3,14", "61", "99%",
                      "1 000", "1 234 567", "1e5", "-0,5"):
            self.assertTrue(gdoc.is_number(value), value)

    def test_not_numbers(self):
        for value in ("", "  ", "Итого", "12.05.2024", "0.0.1", "-,5",
                      "1 2 3", "FreeCad", "#DIV/0!", "nan", "NaN", "inf",
                      "-inf", "infinity", "1_000", "１２３", "0x10", "5-"):
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
        self.assertNotIn("<script>", gdoc._table([["<script>"]], "Л"))

    def test_caption_escaped(self):
        self.assertNotIn("<b>", gdoc._table([["x"]], "<b>лист</b>"))


def _pptx(slide_body: str, media: dict[str, bytes] | None = None,
          rels: str = "") -> io.BytesIO:
    """Минимальная презентация в памяти."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("ppt/presentation.xml",
                    '<p:presentation xmlns:p="http://schemas.openxmlformats.org'
                    '/presentationml/2006/main" xmlns:r="http://schemas.openxml'
                    'formats.org/officeDocument/2006/relationships">'
                    '<p:sldIdLst><p:sldId r:id="rId1"/></p:sldIdLst>'
                    "</p:presentation>")
        zf.writestr("ppt/_rels/presentation.xml.rels",
                    '<Relationships><Relationship Id="rId1" '
                    'Target="slides/slide1.xml"/></Relationships>')
        zf.writestr("ppt/slides/slide1.xml",
                    '<p:sld xmlns:p="http://schemas.openxmlformats.org/present'
                    'ationml/2006/main" xmlns:a="http://schemas.openxmlformats'
                    '.org/drawingml/2006/main" xmlns:r="http://schemas.openxml'
                    'formats.org/officeDocument/2006/relationships">'
                    f"<p:cSld><p:spTree>{slide_body}</p:spTree></p:cSld></p:sld>")
        zf.writestr("ppt/slides/_rels/slide1.xml.rels",
                    f"<Relationships>{rels}</Relationships>")
        for name, data in (media or {}).items():
            zf.writestr(f"ppt/media/{name}", data)
    buf.seek(0)
    return buf


def _sp(text: str, kind: str = "body", lvl: str = "0") -> str:
    return (f'<p:sp><p:nvSpPr><p:nvPr><p:ph type="{kind}"/></p:nvPr></p:nvSpPr>'
            f'<a:p><a:pPr lvl="{lvl}"/><a:r><a:t>{text}</a:t></a:r></a:p></p:sp>')


class TestPptx(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def _render(self, archive: io.BytesIO) -> str:
        path = self.out / "deck.pptx"
        path.write_bytes(archive.getvalue())
        return gdoc.render_pptx(path, self.out)

    def test_title_becomes_heading(self):
        out = self._render(_pptx(_sp("Заголовок", "title")))
        self.assertIn("<h2>Заголовок</h2>", out)

    def test_paragraphs_are_not_turned_into_lists(self):
        body = ('<p:sp><p:nvSpPr><p:nvPr/></p:nvSpPr>'
                "<a:p><a:r><a:t>раз</a:t></a:r></a:p>"
                "<a:p><a:r><a:t>два</a:t></a:r></a:p></p:sp>")
        out = self._render(_pptx(body))
        self.assertNotIn("<ul>", out)
        self.assertEqual(out.count("<p"), 2)

    def test_list_level_becomes_indent(self):
        out = self._render(_pptx(_sp("вложенный", lvl="2")))
        self.assertIn('class="lvl2"', out)

    def test_table_stays_a_table(self):
        body = ('<p:graphicFrame><a:tbl>'
                "<a:tr><a:tc><a:p><a:r><a:t>A1</a:t></a:r></a:p></a:tc>"
                "<a:tc><a:p><a:r><a:t>B1</a:t></a:r></a:p></a:tc></a:tr>"
                "</a:tbl></p:graphicFrame>")
        out = self._render(_pptx(body))
        self.assertIn("<table>", out)
        self.assertEqual(out.count("<td>"), 2)
        self.assertIn("A1", out)

    def test_embedded_picture_rendered(self):
        body = ('<p:pic><p:blipFill><a:blip r:embed="rId9"/></p:blipFill></p:pic>')
        rels = '<Relationship Id="rId9" Target="../media/pic.png"/>'
        out = self._render(_pptx(body, {"pic.png": _png()}, rels))
        self.assertIn('src="media/pic.png"', out)
        self.assertTrue((self.out / "media" / "pic.png").exists())

    def test_unresolvable_picture_is_reported(self):
        body = '<p:pic><p:blipFill><a:blip r:embed="rId9"/></p:blipFill></p:pic>'
        out = self._render(_pptx(body, {}, '<Relationship Id="rId9" '
                                          'Target="http://evil/x.png"/>'))
        self.assertIn("не вложено", out)

    def test_empty_slide_is_reported(self):
        self.assertIn("без текста", self._render(_pptx("")))

    def test_text_is_escaped(self):
        self.assertNotIn("<script>", self._render(_pptx(_sp("<script>"))))

    def test_not_a_zip(self):
        path = self.out / "fake.pptx"
        path.write_bytes(b"not a zip at all")
        with self.assertRaises(gdoc.RenderError):
            gdoc.render_pptx(path, self.out)

    def test_oversized_media_skipped(self):
        big = b"\x00" * 4096
        with mock.patch.object(gdoc, "MAX_MEDIA_BYTES", 1024):
            out = self._render(_pptx(_sp("t"), {"huge.png": big}))
        self.assertIn("Не распаковано вложений", out)
        self.assertFalse((self.out / "media" / "huge.png").exists())


class TestSlugify(unittest.TestCase):
    def test_keeps_cyrillic_and_replaces_separators(self):
        self.assertEqual(gdoc.slugify("отчёт по работе"), "отчёт_по_работе")

    def test_strips_leading_dots(self):
        self.assertFalse(gdoc.slugify(".hidden").startswith("."))

    def test_never_empty(self):
        self.assertEqual(gdoc.slugify("///"), "doc")

    def test_length_capped(self):
        self.assertLessEqual(len(gdoc.slugify("x" * 200)), 48)


class TestLooksLikeDir(unittest.TestCase):
    def test_trailing_slash(self):
        self.assertTrue(gdoc.looks_like_dir("/tmp/нет-такого/"))

    def test_plain_name_is_not_a_dir(self):
        self.assertFalse(gdoc.looks_like_dir("/tmp/нет-такого"))

    def test_existing_directory(self):
        self.assertTrue(gdoc.looks_like_dir(tempfile.gettempdir()))


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
        self.assertEqual(gdoc.cache_dir(self.doc), gdoc.cache_dir(self.doc))

    def test_changes_when_content_changes(self):
        before = gdoc.cache_dir(self.doc)
        self.doc.write_bytes(b"hello world")
        self.assertNotEqual(before, gdoc.cache_dir(self.doc))

    def test_fingerprint_tracks_layout(self):
        before = gdoc.renderer_fingerprint()
        with mock.patch.object(gdoc, "PAGE_CSS", gdoc.PAGE_CSS + "\np{}"):
            self.assertNotEqual(before, gdoc.renderer_fingerprint())

    def test_fingerprint_tracks_source_code(self):
        # Правка логики рендера меняет вывод так же, как правка CSS.
        before = gdoc.renderer_fingerprint()
        with mock.patch.object(gdoc, "_source_digest", lambda: "другой"):
            self.assertNotEqual(before, gdoc.renderer_fingerprint())

    def test_fingerprint_tracks_converter_path(self):
        before = gdoc.renderer_fingerprint()
        with mock.patch.object(gdoc, "PANDOC", "/nix/store/другой/pandoc"):
            self.assertNotEqual(before, gdoc.renderer_fingerprint())

    def _fill(self, count: int) -> None:
        root = gdoc.cache_root()
        root.mkdir(parents=True, exist_ok=True)
        for i in range(count):
            entry = root / f"doc{i:03d}-{i:016x}"
            entry.mkdir()
            os.utime(entry, (i, i))

    def test_prune_keeps_newest(self):
        self._fill(gdoc.CACHE_KEEP + 5)
        gdoc.prune_cache()
        left = [d for d in gdoc.cache_root().iterdir() if not d.name.startswith(".")]
        self.assertEqual(len(left), gdoc.CACHE_KEEP)

    def test_prune_spares_fresh_staging(self):
        self._fill(2)
        staging = gdoc.cache_root() / ".tmp-1-doc"
        staging.mkdir()
        gdoc.prune_cache()
        self.assertTrue(staging.exists())

    def test_prune_collects_abandoned_staging(self):
        # Каталог от убитого процесса иначе не удалит никто и никогда.
        self._fill(2)
        staging = gdoc.cache_root() / ".tmp-999999-doc"
        staging.mkdir()
        old = time.time() - gdoc.STAGING_MAX_AGE - 60
        os.utime(staging, (old, old))
        gdoc.prune_cache()
        self.assertFalse(staging.exists())

    def test_prune_spares_recently_used_entries(self):
        # Свежая запись — это та, которой кто-то прямо сейчас пользуется,
        # в том числе другой процесс.
        self._fill(gdoc.CACHE_KEEP + 5)
        fresh = gdoc.cache_root() / "doc000-0000000000000000"
        os.utime(fresh)
        gdoc.prune_cache()
        self.assertTrue(fresh.exists())

    def test_staging_age_cannot_outlive_a_running_process(self):
        self.assertGreater(gdoc.STAGING_MAX_AGE,
                           gdoc.RUN_TIMEOUT + gdoc.PRINT_TIMEOUT)


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

        self.fmt = gdoc.Format("fake", render)
        self.patch = mock.patch.dict(gdoc.FORMATS, {".fake": self.fmt})
        self.patch.start()
        self.printed = mock.patch.object(
            gdoc, "to_pdf",
            side_effect=lambda index, pdf: pdf.write_bytes(b"%PDF-1.4\n"))
        self.printed.start()

    def tearDown(self):
        self.printed.stop()
        self.patch.stop()
        os.environ.pop("XDG_CACHE_HOME", None)
        self.tmp.cleanup()

    def test_builds_html_and_pdf(self):
        pdf = gdoc.build(self.doc)
        self.assertTrue(pdf.exists())
        self.assertTrue((pdf.parent / "index.html").exists())
        self.assertEqual(pdf.name, "файл.pdf")

    def test_second_run_uses_cache(self):
        gdoc.build(self.doc)
        gdoc.build(self.doc)
        self.assertEqual(len(self.calls), 1)

    def test_force_rerenders(self):
        gdoc.build(self.doc)
        gdoc.build(self.doc, force=True)
        self.assertEqual(len(self.calls), 2)

    def test_html_only_skips_pdf(self):
        index = gdoc.build(self.doc, as_pdf=False)
        self.assertEqual(index.name, "index.html")
        self.assertFalse((index.parent / "файл.pdf").exists())

    def test_no_staging_left_behind(self):
        gdoc.build(self.doc)
        leftovers = [d.name for d in gdoc.cache_root().iterdir()
                     if d.name.startswith(".")]
        self.assertEqual(leftovers, [])

    def test_staging_removed_when_render_fails(self):
        with mock.patch.dict(gdoc.FORMATS, {".fake": gdoc.Format(
                "fake", mock.Mock(side_effect=gdoc.RenderError("сломалось")))}):
            with self.assertRaises(gdoc.RenderError):
                gdoc.build(self.doc)
        self.assertEqual(list(gdoc.cache_root().iterdir()), [])

    def test_loser_of_a_race_uses_the_winners_result(self):
        # Каталог уже занят другим процессом: это не ошибка.
        out = gdoc.cache_dir(self.doc)
        out.mkdir(parents=True)
        (out / "index.html").write_text("чужой", encoding="utf-8")
        pdf = gdoc.build(self.doc)
        self.assertEqual(pdf.parent, out)
        self.assertEqual((out / "index.html").read_text(encoding="utf-8"), "чужой")
        self.assertEqual(self.calls, [])

    def test_real_publish_error_is_reported(self):
        # ENOSPC/EROFS не должны маскироваться под «нас опередили».
        with mock.patch.object(Path, "replace",
                               side_effect=OSError(errno.EROFS, "Read-only file system")):
            with self.assertRaises(gdoc.RenderError) as caught:
                gdoc.build(self.doc)
        self.assertIn("Read-only", str(caught.exception))

    def test_partial_cache_entry_is_rebuilt(self):
        out = gdoc.cache_dir(self.doc)
        out.mkdir(parents=True)
        (out / "мусор").write_text("", encoding="utf-8")
        gdoc.build(self.doc)
        self.assertTrue((out / "index.html").exists())

    def test_empty_pdf_is_reprinted(self):
        pdf = gdoc.build(self.doc)
        pdf.write_bytes(b"")
        gdoc.build(self.doc)
        self.assertGreater(pdf.stat().st_size, 0)

    def test_empty_file_is_refused(self):
        # Иначе часть конвертеров отдаёт чистый лист и rc=0.
        empty = Path(self.tmp.name) / "пусто.fake"
        empty.write_bytes(b"")
        with self.assertRaises(gdoc.RenderError):
            gdoc.build(empty)

    def test_relative_path_reaches_renderer_as_absolute(self):
        # Конвертеры работают из каталога кэша: относительное имя
        # разрешалось бы уже от него, и документ не находился.
        was = os.getcwd()
        os.chdir(self.tmp.name)
        try:
            gdoc.main(["-p", self.doc.name])
        finally:
            os.chdir(was)
        self.assertEqual(self.calls, [self.doc])
        self.assertTrue(self.calls[0].is_absolute())

    def test_unknown_extension_touches_nothing(self):
        other = Path(self.tmp.name) / "x.unknown"
        other.write_bytes(b"x")
        with self.assertRaises(gdoc.RenderError):
            gdoc.build(other)
        self.assertFalse(gdoc.cache_root().exists())


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

    def test_many_files_accept_trailing_slash(self):
        _, args = gdoc.parse_args(["--out", "/nope/dir/", "a.docx", "b.docx"])
        self.assertEqual(args.out, "/nope/dir/")

    def test_force_and_overwrite_are_separate(self):
        _, args = gdoc.parse_args(["-f", "a.docx"])
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
        self.assertEqual(gdoc.export(self.pdf, self.src, str(dest), False),
                         dest / "отчёт за год.pdf")

    def test_trailing_slash_creates_directory(self):
        # Именно строкой: Path срезал бы слэш, и намерение «это каталог»
        # потерялось бы ещё до вызова.
        final = gdoc.export(self.pdf, self.src,
                            str(self.root / "new") + os.sep, False)
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

    def test_overwrite_replaces(self):
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
        for name in ("a.tex", "noext", "a.exe"):
            with self.subTest(name=name):
                with self.assertRaises(gdoc.RenderError):
                    gdoc.pick_format(Path(name))


class TestChromiumCommand(unittest.TestCase):
    """Сетевая изоляция задаётся флагами — значит её надо проверять."""

    def _cmd(self):
        return gdoc._chromium_cmd(Path("/tmp/кэш/index.html"),
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
        cmd = gdoc._chromium_cmd(Path("/tmp/c#1/index.html"),
                                 Path("/tmp/c#1/o.pdf"), Path("/tmp/p"))
        self.assertIn("%23", cmd[-1])
        self.assertNotIn("#1/index.html", cmd[-1])

    def test_sandbox_is_not_disabled_by_default(self):
        self.assertNotIn("--no-sandbox", self._cmd())


class TestPage(unittest.TestCase):
    def test_title_is_escaped(self):
        out = gdoc.page("<script>x</script>", "md", "<p>тело</p>")
        self.assertNotIn("<script>x", out)

    def test_wide_switches_to_landscape(self):
        self.assertIn("A4 landscape", gdoc.page("t", "xlsx", "", wide=True))
        self.assertNotIn("landscape", gdoc.page("t", "docx", ""))

    def test_own_script_is_present(self):
        self.assertIn("fitMath", gdoc.page("t", "md", "<p>x</p>"))


if __name__ == "__main__":
    unittest.main()
