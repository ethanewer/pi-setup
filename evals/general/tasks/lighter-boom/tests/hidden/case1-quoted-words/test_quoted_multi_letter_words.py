"""Hidden case 1: quoted multi-letter words, including capitalized / text-initial.

The upstream regression test quotes 'Hard' and 'hello' mid-sentence. This
case pushes the same opening-quote padding rule off the golden test's inputs:
capitalized words in all-caps-triggering position, text-initial quotes, and a
sentence-initial quoted word -- all through the tokenizer the fix lives in.
"""
from nltk.tokenize import NLTKWordTokenizer

TOKENIZER = NLTKWordTokenizer()


def test_twas_brillig():
    toks = TOKENIZER.tokenize("'Twas 'brillig', and the slithy toves")
    assert toks == ["'", "Twas", "'", "brillig", "'", ",", "and", "the", "slithy", "toves"], toks


def test_bout_time():
    toks = TOKENIZER.tokenize("'Bout time")
    assert toks == ["'", "Bout", "time"], toks


def test_goodbye_mid_sentence():
    toks = TOKENIZER.tokenize("He said 'goodbye' forever")
    assert toks == ["He", "said", "'", "goodbye", "'", "forever"], toks


def test_unclosed_initial_quote():
    toks = TOKENIZER.tokenize("'hello")
    assert toks == ["'", "hello"], toks