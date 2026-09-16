#!/usr/bin/env python3
"""Runtime probe: succeeds only when the memory-zone exception-cleanup bug is
PRESENT in the compiled extension modules (vocab stuck in zone state, leak).
Succeeds on the reverted parent tree, so the verifier can prove the pre-fix
state it is about to test is genuinely the buggy state and not a stale
no-op rebuild."""
import sys

from spacy.vocab import Vocab

vocab = Vocab()
_ = vocab["dog"]
try:
    with vocab.memory_zone():
        _ = vocab["horse"]
        raise ValueError("probe")
except ValueError:
    pass

assert vocab.in_memory_zone, "expected the bug to be present (zone stuck)"
print("PARENT-PROBE-OK")
sys.exit(0)