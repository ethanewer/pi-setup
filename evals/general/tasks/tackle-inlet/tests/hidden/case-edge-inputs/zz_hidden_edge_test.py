"""Hidden case 2 for tackle-inlet: the empty-string guard must be narrow.

Passing an empty string must not touch how the stemmer treats any non-empty
input: whitespace, tabs, punctuation, digits and bare accents must pass
through exactly as before, and repeated calls must stay correct. These
inputs never crashed even on the buggy parent, so they can only fail if the
agent's fix changes behaviour beyond the empty case.
"""
import unittest

from nltk.stem.snowball import SnowballStemmer


class TestEdgeInputs(unittest.TestCase):
    def test_whitespace_passes_through(self):
        h = SnowballStemmer("hungarian")
        self.assertEqual(h.stem(" "), " ")
        self.assertEqual(h.stem("\t"), "\t")

    def test_punctuation_digits_accents(self):
        h = SnowballStemmer("hungarian")
        self.assertEqual(h.stem("-"), "-")
        self.assertEqual(h.stem(", "), ", ")
        self.assertEqual(h.stem("1"), "1")
        self.assertEqual(h.stem("é"), "é")

    def test_empty_after_nonempty(self):
        h = SnowballStemmer("hungarian")
        self.assertEqual(h.stem("sarki"), "sar")
        self.assertEqual(h.stem(""), "")
        self.assertEqual(h.stem("tudnék"), "tudne")

    def test_default_ignore_stopwords_constructor(self):
        h = SnowballStemmer("hungarian", ignore_stopwords=False)
        self.assertEqual(h.stem(""), "")
        self.assertEqual(h.stem("van"), "van")
        self.assertEqual(h.stem("sarki"), "sar")

    def test_two_instances_stay_independent(self):
        h1 = SnowballStemmer("hungarian")
        h2 = SnowballStemmer("hungarian")
        self.assertEqual(h1.stem(""), "")
        self.assertEqual(h2.stem("házak"), "ház")


if __name__ == "__main__":
    unittest.main()