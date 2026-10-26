import tempfile
import unittest
from pathlib import Path

from check_ui_text import check_file, inspect_text


class UiTextPolicyTests(unittest.TestCase):
    def test_russian_text_and_wow_markup(self):
        self.assertFalse(inspect_text('Кнопка: Ёж, ёлка — «текст»… 90° |cffff0000цвет|r <tag x="1"/>'))

    def test_missing_glyph_candidates(self):
        for char in ('−', '→', '■', '●', '✓', '😀'):
            with self.subTest(char=char):
                self.assertTrue(inspect_text(char))

    def test_hidden_characters_and_replacement(self):
        for char in ('\ufeff', '\u200b', '\u202e', '\u00a0', '\ufffd', '\x00'):
            with self.subTest(char=repr(char)):
                self.assertTrue(inspect_text(char))

    def test_escaped_glyphs(self):
        for value in (r'"\226\136\146"', r'"\xE2\x88\x92"', r'"\u{2212}"', '&#x2212;', '&#8722;'):
            with self.subTest(value=value):
                self.assertTrue(inspect_text(value))
        self.assertFalse(inspect_text(r'"[\128-\191]"'))

    def test_double_decoded_cyrillic(self):
        damaged = 'Тестирование'.encode('utf-8').decode('cp1251')
        self.assertTrue(inspect_text(damaged))

    def test_invalid_utf8(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.lua'
            path.write_bytes(b'"\xff"')
            self.assertIn('Invalid UTF-8', check_file(path)[0][1])


if __name__ == '__main__':
    unittest.main()
