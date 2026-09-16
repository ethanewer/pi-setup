#!/usr/bin/env python3
"""Hidden case 1 (gaff-boom): the StringStore-level memory-zone path with an
exception, which the upstream regression test never reaches directly (it only
goes through Vocab.memory_zone). Exercises the cleanup of the second context
manager the fix hardens, using words the upstream test does not use."""
import sys

from spacy.strings import StringStore

store = StringStore()
k_alpha = store.add("alpha")
assert k_alpha != 0 and "alpha" in store
# A zone that fails mid-way, AFTER adding a transient string.
try:
    with store.memory_zone():
        k_beta = store.add("beta")
        assert "beta" in store
        raise RuntimeError("boom")
except RuntimeError:
    pass

if "beta" in store:
    print("FAIL: transient string leaked after failed memory zone")
    sys.exit(1)
assert "alpha" in store, "pre-existing string lost"
assert store.as_int("alpha") == k_alpha, "pre-existing string hash changed"

# The store must be out of zone mode: a new addition must persist.
k_delta = store.add("delta")
assert "delta" in store and store.as_int("delta") == k_delta, "store still in zone mode"

# A subsequent NORMAL zone must still work and free its transient strings.
with store.memory_zone():
    k_gamma = store.add("gamma")
    assert "gamma" in store
assert "gamma" not in store, "normal zone did not free its transient string"
# And the store is still fully usable.
assert "alpha" in store and "delta" in store
assert store.as_int("alpha") == k_alpha
print("HIDDEN-STRINGSTORE-OK")
sys.exit(0)