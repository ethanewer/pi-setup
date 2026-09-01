#!/usr/bin/env python3
"""Hidden-case check for Stage 1 (vocabulary frequency filtering).

Re-runs the agent's /app/build_vocab.py on a fresh hidden corpus and asserts:
(1) all 25 required terms survive even on the fresh corpus;
(2) a required term whose raw count is 1 (— yarrowkeep) is still retained;
(3) single-occurrence filler words are filtered out at --min-count 2;
(4) output is sorted, ends with a newline, and is not pathologically large.
"""
import subprocess
import sys

sys.path.insert(0, "/tests")
from check_terms import REQUIRED_TERMS

BUILD = "/app/build_vocab.py"
CORPUS = "/tests/hidden/hidden_corpus.txt"
OUT = "/tmp/vocab_hidden.txt"

REQUIRED = set(REQUIRED_TERMS)
SINGLES = {"zygomeres", "opulentia", "quagmirewise", "thorfinnstone",
           "brindleux", "yodelworth", "mossopolis", "dapplemote", "whisp",
           "gnarledge", "kettspar", "veldwain", "coterreel", "asperfolia",
           "grignardway"}


def main():
    p = subprocess.run(
        ["python3", BUILD, "--corpus", CORPUS, "--out", OUT, "--min-count", "2"],
        capture_output=True, text=True)
    if p.returncode != 0:
        print("FAIL build_vocab returned %d: %s" % (p.returncode, p.stderr[-400:]))
        return 1
    try:
        data = open(OUT, encoding="utf-8").read()
    except FileNotFoundError:
        print("FAIL output file missing:", OUT)
        return 1
    words = data.split()
    if not words:
        print("FAIL empty vocabulary")
        return 1
    wset = set(words)
    if not (REQUIRED <= wset):
        print("FAIL missing required terms:", sorted(REQUIRED - wset))
        return 1
    if "yarrowkeep" not in wset:
        print("FAIL yarrowkeep (count-1 required term) not retained")
        return 1
    leaked = wset & SINGLES
    if leaked:
        print("FAIL single-occurrence filler retained:", sorted(leaked))
        return 1
    if words != sorted(words):
        print("FAIL vocabulary not sorted")
        return 1
    if not data.endswith("\n"):
        print("FAIL vocabulary lacks trailing newline")
        return 1
    if len(words) > 900:
        print("FAIL vocabulary pathologically large:", len(words))
        return 1
    print("PASS hidden vocab: %d words, required terms kept, singles filtered"
          % len(words))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())