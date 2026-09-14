"""Hidden case 3 for tackle-inlet: the fix must stay scoped to Hungarian.

The upstream regression test checks all languages' empty-string handling; this
case re-checks a data-free subset of the neighbouring stemmers with normal
words from the project's own test suite (test_stem.py) so a fix that patches
the shared machinery and breaks other languages is caught. The expected
stems are the project's own frozen test vectors.
"""
import unittest

from nltk.stem.snowball import SnowballStemmer


class TestOtherLanguagesUntouched(unittest.TestCase):
    def test_empty_string_across_languages(self):
        for lang in ("english", "german", "russian", "spanish", "french"):
            self.assertEqual(SnowballStemmer(lang).stem(""), "")

    def test_normal_stemming_untouched(self):
        self.assertEqual(SnowballStemmer("english").stem("running"), "run")
        self.assertEqual(SnowballStemmer("german").stem("Schr\u00e4nke"), "schrank")
        self.assertEqual(
            SnowballStemmer("russian").stem("\u0430\u0432\u0430\u043d\u0442\u043d\u0435\u043d\u044c\u043a\u0430\u044f"),
            "\u0430\u0432\u0430\u043d\u0442\u043d\u0435\u043d\u044c\u043a",
        )
        self.assertEqual(SnowballStemmer("spanish").stem("Visionado"), "vision")

    def test_spanish_short_string_history(self):
        # The project's own suite documents that 'algue' used to raise
        # IndexError; it must still stem cleanly after this fix.
        self.assertEqual(SnowballStemmer("spanish").stem("algue"), "algu")


if __name__ == "__main__":
    unittest.main()