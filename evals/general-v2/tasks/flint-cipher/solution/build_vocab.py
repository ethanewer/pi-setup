#!/usr/bin/env python3
"""Build a token vocabulary from a plain-text corpus with frequency filtering.

The output vocabulary keeps every token whose frequency is at or above
`--min-count` plus every term in the REQUIRED set (the twenty-five terms that
must always survive even when their raw frequency sits below the threshold).
Tokens are normalised to lower case; words are split on any run of
non-alphanumeric characters; blank lines and stray punctuation are ignored.
A corpus that is empty, or that leaves nothing above the floor, still lands on
the required terms.
"""
import argparse
import re
from collections import Counter

# The 25 terms that MUST survive filtering no matter how rare they are.
REQUIRED_TERMS = [
    "aegis", "balmweaver", "calmstone", "dunecrest", "earthenmark",
    "falconquill", "glintshard", "harborward", "ironweald", "junipergate",
    "kelvinvale", "lumenhold", "meridianstone", "northwell", "oakhurst",
    "pebblecrag", "quillwillow", "reedskiff", "slopehollow", "sunveil",
    "thornbraid", "unbarrow", "vaultpine", "wrenshaw", "yarrowkeep",
]

_WORD_RE = re.compile(r"\w+")


def tokenize(text: str):
    return _WORD_RE.findall(text.lower())


def main() -> int:
    ap = argparse.ArgumentParser(description="build a filtered word vocabulary")
    ap.add_argument("--corpus", required=True, help="path to plain-text corpus")
    ap.add_argument("--out", required=True, help="output vocabulary file path")
    ap.add_argument("--min-count", type=int, default=2, help="frequency floor")
    args = ap.parse_args()

    with open(args.corpus, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()

    counts = Counter(tokenize(text))

    vocab = [tok for tok, n in counts.items() if n >= args.min_count]
    have = set(vocab)
    for term in REQUIRED_TERMS:
        if term not in have:
            vocab.append(term)
            have.add(term)

    vocab.sort()
    with open(args.out, "w", encoding="utf-8") as fh:
        if vocab:
            fh.write("\n".join(vocab) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())