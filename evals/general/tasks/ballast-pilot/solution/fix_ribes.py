#!/usr/bin/env python3
"""Apply the RIBES empty-input fix to nltk/translate/ribes_score.py.

The pre-fix scorer divides by the hypothesis token count (brevity penalty and
unigram precision) and by the number of hypotheses, without guarding against
zero, so an empty hypothesis, an empty reference list or an empty corpus
raises ZeroDivisionError (and an empty reference list silently scores -1.0).
The fixed functions return 0.0 for any empty input and reject a corpus whose
reference-set count does not match its hypothesis count with a ValueError.

Idempotent; exits non-zero if the expected pre-fix code is missing.
"""

import sys
from pathlib import Path

SENT_OLD = """    best_ribes = -1.0
    # Calculates RIBES for each reference and returns the best score.
    for reference in references:"""

SENT_NEW = """    if not references or not hypothesis:
        return 0.0

    best_ribes = -1.0
    # Calculates RIBES for each reference and returns the best score.
    for reference in references:"""

CORPUS_OLD = """    corpus_best_ribes = 0.0
    # Iterate through each hypothesis and their corresponding references.
    for references, hypothesis in zip(list_of_references, hypotheses):"""

CORPUS_NEW = """    if not hypotheses:
        return 0.0
    if len(list_of_references) != len(hypotheses):
        raise ValueError(
            "The number of reference sets must match the number of hypotheses."
        )

    corpus_best_ribes = 0.0
    # Iterate through each hypothesis and their corresponding references.
    for references, hypothesis in zip(list_of_references, hypotheses):"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_ribes.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if SENT_NEW in src and CORPUS_NEW in src:
        print("ribes_score.py already carries the empty-input guards")
        return 0
    if SENT_OLD not in src or CORPUS_OLD not in src:
        print("FATAL: expected pre-fix RIBES code not found", file=sys.stderr)
        return 1
    src = src.replace(SENT_OLD, SENT_NEW, 1)
    src = src.replace(CORPUS_OLD, CORPUS_NEW, 1)
    path.write_text(src, encoding="utf-8")
    print("applied RIBES empty-input guards to ribes_score.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())