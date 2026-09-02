#!/usr/bin/env python3
"""Hidden-case check for Stage 2 (deterministic, bounded BPE tokenizer).

Re-runs the agent's /app/build_tokenizer.py on a fresh hidden corpus twice and
asserts:
(1) training is deterministic (same model vocab size and identical encodings);
(2) the saved model reloads and encodes/decodes an input sentence round-trip;
(3) the vocabulary stays within the requested bounds;
(4) a tiny edge corpus trains and reloads without crashing.
"""
import subprocess
import sys

from tokenizers import Tokenizer

BUILD = "/app/build_tokenizer.py"
CORPUS = "/tests/hidden/hidden_corpus.txt"
TINY = "/tests/hidden/tiny_corpus.txt"
M1, M2 = "/tmp/bpe_1.model", "/tmp/bpe_2.model"

CAP = 512
PROBE = "the meridianstone stood calm by the grove and the vaultpine held"


def train(model_path, corpus):
    p = subprocess.run(
        ["python3", BUILD, "--corpus", corpus, "--out", model_path,
         "--vocab-size", str(CAP), "--min-frequency", "1"],
        capture_output=True, text=True)
    if p.returncode != 0:
        print("FAIL build_tokenizer rc=%d %s" % (p.returncode, p.stderr[-400:]))
        return False
    return True


def main():
    if not (train(M1, CORPUS) and train(M2, CORPUS)):
        return 1

    tok1 = Tokenizer.from_file(M1)
    tok2 = Tokenizer.from_file(M2)

    v1, v2 = len(tok1.get_vocab()), len(tok2.get_vocab())
    print("  vocab sizes:", v1, v2)
    if not (v1 == v2):
        print("FAIL determinism: vocab sizes differ", v1, v2); return 1
    if v1 > CAP + 200:
        print("FAIL vocabulary too large:", v1, "cap", CAP); return 1

    enc1 = tok1.encode(PROBE).ids
    enc2 = tok2.encode(PROBE).ids
    if enc1 != enc2:
        print("FAIL determinism: encodings differ"); return 1

    rebuilt = tok1.decode(enc1, skip_special_tokens=False)
    if rebuilt.strip() != PROBE:
        print("FAIL round-trip: %r -> %r" % (PROBE, rebuilt)); return 1

    # tiny edge corpus must also train/reload without crashing
    if not train("/tmp/bpe_tiny.model", TINY):
        return 1
    try:
        tt = Tokenizer.from_file("/tmp/bpe_tiny.model")
        tiny_text = open(TINY, encoding="utf-8").read()
        _ = tt.encode(tiny_text).ids
    except Exception as exc:
        print("FAIL tiny corpus crash:", exc); return 1

    print("PASS bpe-hidden: deterministic, bounded (<=%d), round-trip, tiny ok" % (CAP + 200))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())