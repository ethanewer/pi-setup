#!/usr/bin/env python3
"""Runtime probe: succeeds only when the memory-zone exception-cleanup bug is
FIXED in the compiled extension modules. Used by the verifier after every
rebuild to prove the rebuild actually took effect and the live binaries match
the state the verifier believes it created."""
import sys

from spacy.vocab import Vocab

vocab = Vocab()
_ = vocab["dog"]
assert "dog" in vocab
try:
    with vocab.memory_zone():
        _ = vocab["horse"]
        raise ValueError("probe")
except ValueError:
    pass

if vocab.in_memory_zone:
    print("FAIL: vocab stuck in memory-zone state (bug present)")
    sys.exit(1)
if "horse" in vocab:
    print("FAIL: transient word leaked after failed memory zone")
    sys.exit(1)
assert "dog" in vocab
lex = vocab["cat"]
assert lex.text == "cat"
print("FIXED-PROBE-OK")
sys.exit(0)