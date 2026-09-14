"""Hidden case 3: the word_tokenize path (Punkt sentence splitter + the
quote-padding tokenizer) on inputs the upstream regression test does not use.

word_tokenize routes through nltk.tokenize.word_tokenize, which first
sentences with Punkt (punkt_tab model, seeded in the image) and then runs the
same quote-padding rule under test.
"""
from nltk.tokenize import word_tokenize


def test_quoted_question():
    toks = word_tokenize("'Really?' he asked")
    assert toks == ["'", "Really", "?", "'", "he", "asked"], toks


def test_two_quoted_words_with_period():
    toks = word_tokenize("'quality' over 'quantity'.")
    assert toks == ["'", "quality", "'", "over", "'", "quantity", "'", "."], toks