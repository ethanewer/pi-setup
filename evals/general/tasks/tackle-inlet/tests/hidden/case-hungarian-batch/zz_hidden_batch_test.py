"""Hidden case 1 for tackle-inlet: the Hungarian Snowball stemmer must handle
the empty string AND keep stemming ordinary Hungarian words correctly.

The upstream regression test only stems the empty string. These cases push the
same code path with a batch of non-empty Hungarian words (case, accents,
digraphs) interleaved with empty strings, so a fix that merely swallows the
crash -- or returns the wrong stem for real words -- is caught here. Expected
stems are the outputs of the fixed upstream stemmer, frozen at authoring time.
"""
import unittest

from nltk.stem.snowball import SnowballStemmer


class TestHungarianBatch(unittest.TestCase):
    def test_empty_string_in_batch(self):
        h = SnowballStemmer("hungarian")
        # repeated and interleaved with real words
        self.assertEqual(h.stem(""), "")
        self.assertEqual(h.stem("sarki"), "sar")
        self.assertEqual(h.stem(""), "")
        self.assertEqual(h.stem(""), "")

    def test_case_accents_and_suffixes(self):
        h = SnowballStemmer("hungarian")
        self.assertEqual(h.stem("SARKI"), "sar")          # case folding
        self.assertEqual(h.stem("tudnék"), "tudne")        # accented stem
        self.assertEqual(h.stem("házak"), "ház")
        self.assertEqual(h.stem("megszámláltam"), "megszámlált")
        self.assertEqual(h.stem("láthatóan"), "látható")

    def test_digraphs(self):
        h = SnowballStemmer("hungarian")
        self.assertEqual(h.stem("szabad"), "szab")         # digraph sz
        self.assertEqual(h.stem("szám"), "szám")

    def test_fresh_instances(self):
        for _ in range(3):
            self.assertEqual(SnowballStemmer("hungarian").stem(""), "")

    def test_empty_does_not_swallow_callers(self):
        h = SnowballStemmer("hungarian")
        out = [h.stem(w) for w in ["sarki", "", "házak", "láthatóan"]]
        self.assertEqual(out, ["sar", "", "ház", "látható"])


if __name__ == "__main__":
    unittest.main()