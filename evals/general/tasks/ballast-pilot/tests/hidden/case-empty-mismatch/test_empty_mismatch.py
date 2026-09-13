"""Hidden case for ballast-pilot: empty and mismatched input shapes the
upstream regression tests do not use.

The upstream tests cover `sentence_ribes([["a"], ["b"]], [])` (single-token
references + empty hypothesis), `sentence_ribes([], ["a"])` (empty reference
list) and `corpus_ribes([[["a"]]], [["a"], ["b"]])` (fewer reference sets than
hypotheses).  These cases drive the same fixed code paths from different
inputs: multi-token references with an empty hypothesis, a completely empty
sentence-level call, a corpus whose single sentence has an empty reference
list, a corpus with *more* reference sets than hypotheses (the reverse of the
upstream mismatch), and a mismatch involving multi-token sentences.  Every
empty shape must yield the exact float 0.0 -- never an exception, never -1.0 --
and every mismatch must raise a ValueError that names the reference sets.
"""

import pytest

from nltk.translate.ribes_score import corpus_ribes, sentence_ribes


def test_empty_hypothesis_with_multi_token_references() -> None:
    # Upstream used single-token references; multi-token references must hit
    # the same guard and yield an exact float, not an exception.
    score = sentence_ribes([["the", "cat"], ["a", "grey", "cat"]], [])
    assert isinstance(score, float)
    assert score == 0.0


def test_fully_empty_sentence_call() -> None:
    # No references at all AND no hypothesis tokens: the pre-fix code returned
    # -1.0 here (its sentinel), which is impossible for a normalized metric.
    assert sentence_ribes([], []) == 0.0


def test_empty_reference_list_single_hypothesis() -> None:
    assert sentence_ribes([], ["a"]) == 0.0


def test_corpus_with_one_empty_reference_list_sentence() -> None:
    # One sentence whose reference list is empty and whose hypothesis is one
    # token: the pre-fix code scored the sentence as -1.0 and returned -1.0.
    assert corpus_ribes([[]], [["a"]]) == 0.0


def test_corpus_with_one_empty_hypothesis_sentence() -> None:
    # One sentence whose hypothesis is empty but whose references are
    # multi-token: corpus must score that sentence 0.0 and average to 0.0.
    assert corpus_ribes([[["the", "cat"]]], [[]]) == 0.0


def test_mismatch_more_reference_sets_than_hypotheses_raises() -> None:
    # Reverse of the upstream mismatch shape (ref sets > hypotheses).
    with pytest.raises(ValueError, match="reference sets"):
        corpus_ribes([[["a"]], [["b"]]], [["a"]])


def test_mismatch_with_multi_token_sentences_raises_before_scoring() -> None:
    # The mismatch must be detected up front: the scorer must raise even though
    # the first pair alone would be scorable, and the message must name the
    # reference sets.
    with pytest.raises(ValueError, match=r"reference sets must match"):
        corpus_ribes([[["a", "b"], ["x", "y"]]], [["a"], ["b", "c"]])