#!/usr/bin/env python3
"""Exploratory probe for the RIBES empty-input handling in the /app/src NLTK
checkout.

Prints what the RIBES scorer does with several empty or mismatched inputs.
Empty or missing translations should score 0.0 and a corpus whose reference
sets do not match its hypotheses in number should be rejected with a clear
ValueError, but in this checkout the scorer crashes with a ZeroDivisionError
(or silently returns an impossible negative score) instead.  Exits non-zero
while any of the behaviours is broken, so scripts can depend on the probe.
"""

import sys

from nltk.translate.ribes_score import corpus_ribes, sentence_ribes

MISMATCH = "The number of reference sets must match the number of hypotheses."


def main() -> int:
    failures = 0

    def check(label, expected, fn):
        nonlocal failures
        try:
            got = fn()
        except Exception as e:  # noqa: BLE001 - the probe reports every outcome
            print(f"- {label}: raised {type(e).__name__}: {e}")
            if expected is not None:
                failures += 1
            return
        print(f"- {label}: -> {got!r}")
        if expected is not None:
            if isinstance(expected, type) and isinstance(got, expected):
                return
            if isinstance(expected, tuple) and got == expected:
                return
            if got != expected:
                failures += 1

    def expect_value_error(label):
        nonlocal failures
        try:
            got = corpus_ribes([[["a"]]], [["a"], ["b"]])
        except ValueError as e:
            print(f"- {label}: -> ValueError: {e}")
            if MISMATCH not in str(e):
                failures += 1
        except Exception as e:  # noqa: BLE001
            print(f"- {label}: raised {type(e).__name__}: {e}")
            failures += 1
        else:
            print(f"- {label}: -> {got!r} (silently scored, should have raised)")
            failures += 1

    # 1. empty candidate translation (empty hypothesis)
    check("sentence_ribes([['a']], [])", 0.0,
          lambda: sentence_ribes([["a"]], []))
    # 2. empty reference list for a sentence
    check("sentence_ribes([], ['a'])", 0.0,
          lambda: sentence_ribes([], ["a"]))
    # 3. empty corpus (no references at all, no hypotheses at all)
    check("corpus_ribes([], [])", 0.0,
          lambda: corpus_ribes([], []))
    # 4. corpus whose reference-set count does not match the hypothesis count
    expect_value_error("corpus_ribes([[['a']]], [['a'], ['b']])")

    if failures:
        print(f"PROBE: {failures} case(s) broken")
        return 1
    print("PROBE: all empty-input behaviours correct")
    return 0


if __name__ == "__main__":
    sys.exit(main())