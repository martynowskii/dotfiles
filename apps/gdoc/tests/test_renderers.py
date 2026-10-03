"""Конвертеры форматов: таблицы, числа, pptx, выбор рендерера."""

import io
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

import common
import renderers
from .fixtures import png


class TestIsNumber(unittest.TestCase):
    def test_numbers(self):
        for value in ("1", "-5", "+5", "3.14", "3,14", "61", "99%",
                      "1 000", "1 234 567", "1e5", "-0,5"):
            self.assertTrue(renderers.is_number(value), value)

    def test_not_numbers(self):
        for value in ("", "  ", "Итого", "12.05.2024", "0.0.1", "-,5",
                      "1 2 3", "FreeCad", "#DIV/0!", "nan", "NaN", "inf",
                      "-inf", "infinity", "1_000", "１２３", "0x10", "5-"):
            self.assertFalse(renderers.is_number(value), value)


class TestTable(unittest.TestCase):
    def test_trailing_empty_columns_and_rows_dropped(self):
        rows = [["a", "1", "", ""], ["b", "2", "", ""], ["", "", "", ""]]
        out = renderers._table(rows, "Лист")
        self.assertEqual(out.count("<tr>"), 2)
        self.assertEqual(out.count("<td"), 4)

    def test_numbers_get_class(self):
        out = renderers._table([["Итого", "61"]], "Л")
        self.assertIn('<td class="n">61</td>', out)
        self.assertIn("<td>Итого</td>", out)

    def test_row_limit_reported(self):
        rows = [[str(i)] for i in range(renderers.MAX_ROWS + 10)]
        out = renderers._table(rows, "Л")
        self.assertIn("Показаны первые", out)
        self.assertEqual(out.count("<tr>"), renderers.MAX_ROWS)

    def test_empty_sheet(self):
        self.assertIn("Лист пустой", renderers._table([["", ""]], "Л"))

    def test_cell_content_escaped(self):
        self.assertNotIn("<script>", renderers._table([["<script>"]], "Л"))

    def test_caption_escaped(self):
        self.assertNotIn("<b>", renderers._table([["x"]], "<b>лист</b>"))


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
        return renderers.render_pptx(path, self.out)

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
        out = self._render(_pptx(body, {"pic.png": png()}, rels))
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
        with self.assertRaises(common.RenderError):
            renderers.render_pptx(path, self.out)

    def test_oversized_media_skipped(self):
        big = b"\x00" * 4096
        with mock.patch.object(renderers, "MAX_MEDIA_BYTES", 1024):
            out = self._render(_pptx(_sp("t"), {"huge.png": big}))
        self.assertIn("Не распаковано вложений", out)
        self.assertFalse((self.out / "media" / "huge.png").exists())


class TestPickFormat(unittest.TestCase):
    def test_case_insensitive(self):
        self.assertEqual(renderers.pick_format(Path("A.DOCX")).kind, "docx")

    def test_sheets_are_wide(self):
        self.assertTrue(renderers.pick_format(Path("a.xlsx")).wide)
        self.assertFalse(renderers.pick_format(Path("a.docx")).wide)

    def test_unknown_extension(self):
        for name in ("a.tex", "noext", "a.exe"):
            with self.subTest(name=name):
                with self.assertRaises(common.RenderError):
                    renderers.pick_format(Path(name))
