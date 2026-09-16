"""Hidden case for ballast-pilot: ordinary non-empty inputs must still score
exactly as before the fix.

The upstream regression tests score two long literary sentence pairs through
corpus_ribes.  These cases exercise the same sentence_ribes/corpus_ribes code
paths on short, hand-checkable inputs where the expected value is derivable by
inspection, so they fail loudly if the empty-input guards accidentally distort
genuine scoring or if the author's "fix" simply short-circuits everything to
0.0.

Scoring facts used below (rank-based metric, normalized Kendall tau):
  - a hypothesis identical to its (single) reference has full word order
    alignment, unigram precision 1.0 and brevity penalty 1.0, so its RIBES
    score is exactly 1.0;
  - with no shared tokens the alignment is empty, precision is 0, hence the
    score is exactly 0.0;
  - corpus_ribes is the mean of the per-sentence sentence_ribes scores, so
    repeating a pair must not change the mean, and two pairs average to the
    mean of their individual scores.
"""

import pytest

from nltk.translate.ribes_score import corpus_ribes, sentence_ribes


def test_identical_reference_and_hypothesis_score_exactly_one() -> None:
    ref = ["one", "small", "step", "for", "man"]
    assert sentence_ribes([ref], ref) == 1.0


def test_no_overlap_scores_exactly_zero() -> None:
    assert sentence_ribes([["zzz", "qqq"]], ["aaa", "bbb"]) == 0.0


def test_partial_overlap_scores_strictly_between_zero_and_one() -> None:
    ref = ["one", "small", "step", "for", "man"]
    hyp = ["one", "small", "step", "for", "mankind"]
    score = sentence_ribes([ref], hyp)
    assert 0.0 < score < 1.0


def test_corpus_score_is_the_mean_of_sentence_scores() -> None:
    ref1 = ["one", "small", "step"]
    hyp1 = ["one", "small", "step"]  # identical -> per-sentence 1.0
    ref2 = ["quite", "different"]
    hyp2 = ["not", "the", "same", "thing"]  # no overlap -> 0.0
    pair1 = sentence_ribes([ref1], hyp1)
    pair2 = sentence_ribes([ref2], hyp2)
    assert pair1 == 1.0
    assert pair2 == 0.0
    assert corpus_ribes([[ref1], [ref2]], [hyp1, hyp2]) == pytest.approx(
        (pair1 + pair2) / 2.0
    )


def test_repeating_a_pair_does_not_change_the_corpus_score() -> None:
    ref = ["the", "cat", "sat", "down"]
    hyp = ["the", "cat", "sat", "down"]
    once = corpus_ribes([[ref]], [hyp])
    thrice = corpus_ribes([[ref], [ref], [ref]], [hyp, hyp, hyp])
    assert once == 1.0
    assert thrice == pytest.approx(once)