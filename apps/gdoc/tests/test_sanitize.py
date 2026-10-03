"""Очистка разметки: активное содержимое, ссылки, стили, структура."""

import time
import unittest

import sanitize


def clean(markup: str) -> str:
    """Очищенная разметка без счётчика потерь."""
    return sanitize.sanitize(markup)[0]


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
        _, dropped = sanitize.sanitize('<img src="http://a/1"><img src="/etc/x">')
        self.assertEqual(sum(dropped.values()), 2)

    def test_note_added_when_something_dropped(self):
        body = sanitize.sanitized_body('<img src="http://evil/x">')
        self.assertIn("Вырезано", body)
        self.assertIn("ссылок на внешние ресурсы: 1", body)

    def test_note_mentions_every_kind_of_loss(self):
        body = sanitize.sanitized_body(
            '<img src="http://evil/x">'
            '<iframe src="http://evil/y"></iframe>'
            '<p style="background:url(http://evil/z)">t</p>')
        self.assertIn("ссылок на внешние ресурсы", body)
        self.assertIn("внешних вставок", body)
        self.assertIn("правил оформления", body)

    def test_no_note_when_nothing_dropped(self):
        self.assertNotIn("Вырезано", sanitize.sanitized_body("<p>чисто</p>"))


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
        _, dropped = sanitize.sanitize('<p style="background:url(http://evil/x)">t</p>')
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
        depth = sanitize.MAX_DEPTH * 20
        out = clean("<div>" * depth + "дно" + "</div>" * depth)
        self.assertIn("дно", out)
        self.assertLessEqual(out.count("<div>"), sanitize.MAX_DEPTH)

    def test_deep_nesting_is_fast(self):
        started = time.monotonic()
        clean("<div>" * 20000 + "x" + "</div>" * 20000)
        self.assertLess(time.monotonic() - started, 2.0)

    def test_depth_overflow_is_reported(self):
        deep = "<div>" * (sanitize.MAX_DEPTH + 5) + "дно"
        body = sanitize.sanitized_body(deep)
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
            sanitize._Sanitizer.VOID & sanitize._Sanitizer.DROP_TREE, frozenset())
        self.assertEqual(
            sanitize._Sanitizer.DROP_SELF & sanitize._Sanitizer.DROP_TREE, frozenset())

    def test_dropped_embed_is_counted(self):
        _, dropped = sanitize.sanitize('<embed src="http://evil/x">')
        self.assertEqual(sum(dropped.values()), 1)

    def test_head_dropped_body_kept(self):
        out = clean("<html><head><title>T</title><style>p{}</style></head>"
                    "<body><p>тело</p></body></html>")
        self.assertNotIn("T", out)
        self.assertNotIn("p{}", out)
        self.assertIn("<p>тело</p>", out)
