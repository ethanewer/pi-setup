#!/usr/bin/env python3
"""Hidden case 2 (gaff-boom): a Vocab-level memory zone that accumulates
MULTIPLE transient words before the exception, followed by a successful zone
and sustained vocabulary reuse afterwards. The upstream regression test only
checks one transient word and does not reuse the zone after the failure."""
import sys

from spacy.vocab import Vocab

vocab = Vocab()
for w in ["north", "south", "east"]:
    _ = vocab[w]

try:
    with vocab.memory_zone():
        _ = vocab["west"]
        _ = vocab["northwest"]
        raise AssertionError("simulated failure")
except AssertionError:
    pass

if vocab.in_memory_zone:
    print("FAIL: vocab stuck in memory-zone state after an exception")
    sys.exit(1)
for w in ("west", "northwest"):
    if w in vocab:
        print(f"FAIL: transient word {w!r} leaked from failed memory zone")
        sys.exit(1)
for w in ("north", "south", "east"):
    assert w in vocab and vocab[w].text == w, f"pre-existing word {w!r} damaged"

# Vocabulary fully usable: new, non-transient additions.
lex = vocab["cemetery"]
assert lex.text == "cemetery" and "cemetery" in vocab

# A subsequent normal zone must behave exactly as before the failure.
with vocab.memory_zone():
    _ = vocab["bereavement"]
assert "bereavement" not in vocab, "normal zone did not free its transient word"
assert not vocab.in_memory_zone
assert vocab["cemetery"].text == "cemetery"
print("HIDDEN-VOCAB-REUSE-OK")
sys.exit(0)