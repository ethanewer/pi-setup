"""Deterministic per-client feature material.

The service scores every event against a fixed-length feature vector derived
deterministically from the client's canonical identifier, so the same client
always yields the same material on any host and no external data files are
required.
"""
import functools
import hashlib
import math

EMBED_DIM = 256
DIGEST_LEN = 2048
SEGMENT_COUNT = 6


def _mix(seed):
    """Deterministic pseudo-random floats in [-1, 1] for a small integer seed."""
    state = int.from_bytes(
        hashlib.sha256(("enrichd.mix:%d" % seed).encode("ascii")).digest(),
        "big",
    )
    out = []
    for _ in range(EMBED_DIM):
        state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        out.append(((state >> 11) * (1.0 / (1 << 53))) * 2.0 - 1.0)
    return out


@functools.lru_cache(maxsize=256)
def embedding(client_key):
    """Feature vector for a canonical client key (a tuple of floats)."""
    seed = int(hashlib.sha256(client_key.encode("utf-8")).hexdigest()[:16], 16)
    return tuple(_mix(seed))


def day_ordinal(day):
    """Small integer derived from a YYYY-MM-DD date, used by the fold."""
    return int(day[-2:]) % 28


def build_digest(client_key, day):
    """The daily behaviour digest: a fixed-length deterministic feature fold.

    This is the expensive fold the profile cache exists to memoise: it walks
    the client embedding several times and mixes in calendar-derived weights,
    so per-event recomputation is wasteful when events arrive in bursts.
    Values are pure functions of (client_key, day).
    """
    emb = embedding(client_key)
    d = day_ordinal(day)
    out = [0.0] * DIGEST_LEN
    for i in range(DIGEST_LEN):
        src = (i * 7 + d) % EMBED_DIM
        w = 0.5 + 0.5 * math.sin((i + d + 1) * 0.61803398875)
        out[i] = emb[src] * (2.0 * w) + emb[(src + 13) % EMBED_DIM] * 0.25
    return out
