"""Hidden case 2: contractions and intra-word apostrophes must stay intact
while quoted multi-letter words are padded.

The fix must not regress the clitics and contractions the tokenizer already
handles (it's, don't, isn't, 'n) and must keep intra-word apostrophes
(o'clock-style possessives) whole -- the padding rule fires only on an
opening quote at a word boundary, never inside a word.
"""
from nltk.tokenize import NLTKWordTokenizer

TOKENIZER = NLTKWordTokenizer()


def test_possessive_with_quoted_word():
    toks = TOKENIZER.tokenize("The dog's 'bark' was loud")
    assert toks == ["The", "dog", "'s", "'", "bark", "'", "was", "loud"], toks


def test_contraction_with_two_quoted_words():
    toks = TOKENIZER.tokenize("don't 'worry' 'bout it")
    assert toks == ["do", "n't", "'", "worry", "'", "'", "bout", "it"], toks


def test_quoted_word_containing_contraction():
    toks = TOKENIZER.tokenize("'she's here'")
    assert toks == ["'", "she", "'s", "here", "'"], toks


def test_quoted_word_containing_nt():
    toks = TOKENIZER.tokenize("'don't' stop")
    assert toks == ["'", "do", "n't", "'", "stop"], toks


def test_isnt_still_splits():
    toks = TOKENIZER.tokenize("isn't it")
    assert toks == ["is", "n't", "it"], toks