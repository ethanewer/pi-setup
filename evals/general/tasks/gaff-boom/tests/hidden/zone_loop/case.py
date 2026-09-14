#!/usr/bin/env python3
"""Hidden case 3 (gaff-boom): interleaves several memory zones, with failure
only on one of them, using a different exception type (KeyError) than the
upstream regression test (ValueError). Proves the cleanup restores the vocab
every single time, not just once."""
import sys

from spacy.vocab import Vocab

vocab = Vocab()
_ = vocab["anchor"]

for i in range(4):
    try:
        with vocab.memory_zone():
            _ = vocab[f"buoy{i}"]
            if i == 2:
                raise KeyError("simulated failure")
    except KeyError:
        pass
    if vocab.in_memory_zone:
        print(f"FAIL: vocab stuck in memory-zone state after iteration {i}")
        sys.exit(1)

for i in range(4):
    if f"buoy{i}" in vocab:
        print(f"FAIL: transient word buoy{i} leaked across zone iterations")
        sys.exit(1)

for i in range(3):
    with vocab.memory_zone():
        _ = vocab[f"temporary{i}"]
    if f"temporary{i}" in vocab or vocab.in_memory_zone:
        print("FAIL: normal zone left transient state behind")
        sys.exit(1)

assert "anchor" in vocab and vocab["anchor"].text == "anchor"
assert vocab["keel"].text == "keel"
print("HIDDEN-ZONE-LOOP-OK")
sys.exit(0)