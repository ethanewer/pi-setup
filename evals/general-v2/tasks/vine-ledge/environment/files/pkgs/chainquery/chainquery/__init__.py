"""chainquery: a tiny self-contained ledger-query helper (clean-room synthetic).

Provides a deterministic block-hash -> (height, status) resolver. This is a
stand-in for a real blockchain client library: it has no network dependency,
so it works fully offline and deterministically for the grading harness.

Public API
----------
lookup(block_hash: str) -> dict
    Validate that block_hash is exactly 64 hexadecimal characters (after
    stripping surrounding whitespace and lower-casing). On failure raise
    ValueError with a human-readable message. On success return a dict::

        {"hash": <lowercased 64-hex>, "height": <int>, "status": <str>}

The height and status are derived deterministically from the SHA-256 digest of
the normalized hash::

    digest = sha256(normalized_hash).hexdigest()
    height = int(digest[:8], 16) % 100000
    status = "confirmed" if int(digest[8:16], 16) % 2 == 0 else "pending"

These formulas are part of the task contract and MUST NOT be changed.
"""
from __future__ import annotations

import hashlib

__version__ = "1.2.0"
VERSION = __version__

_HEX = frozenset("0123456789abcdef")


def lookup(block_hash: object) -> dict:
    if not isinstance(block_hash, str):
        raise ValueError("block hash must be a string")
    s = block_hash.strip().lower()
    if len(s) != 64 or any(c not in _HEX for c in s):
        raise ValueError("invalid block hash: must be exactly 64 hexadecimal characters")
    digest = hashlib.sha256(s.encode("ascii")).hexdigest()
    height = int(digest[:8], 16) % 100000
    status = "confirmed" if int(digest[8:16], 16) % 2 == 0 else "pending"
    return {"hash": s, "height": height, "status": status}
