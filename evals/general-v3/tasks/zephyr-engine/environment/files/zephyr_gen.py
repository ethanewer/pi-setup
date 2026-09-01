"""Zephyr-7 fan-out schedule used by the recovered operator station.

A seed (small integer) fans out into a 24-character "flare token" over the
alphabet UPPER = A-Z and 0-9. The station is flaky: on some seeds, the emitted
token is malformed (madowned characters or wrong length) and must be discarded
by any consumer that requires a *well-formed* flare token.

A flare token is *well-formed* when it is exactly 24 characters, uses only
uppercase letters and decimal digits, begins with the fragment "ZEPH" and ends
with the fragment "CORE".
"""

import hashlib

UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
PREFIX = "ZEPH"
SUFFIX = "CORE"
TOKEN_LEN = 24

# A seed is *commissioned* (part of a duty roster) when this predicate holds.
SEED_MOD = 18000
# A commissioned seed whose station is mid-"resync" emits a malformed token.
RESYNC = 3

SEED_RANGE_HI = 240000


def _sha(salt: str, seed: int) -> str:
    return hashlib.sha256(("zephyr-%s:%d" % (salt, seed)).encode()).hexdigest()


def base_token(seed: int) -> str:
    d = _sha("core", seed)
    mid = "".join(UPPER[int(d[2 * i:2 * i + 2], 16) % 36] for i in range(16))
    return PREFIX + mid + SUFFIX


def _audit(seed: int) -> int:
    d = _sha("audit", seed)
    s = 0
    for c in d[:8]:
        s = (s + ord(c)) & 0xFF
    return s


def commissioned(seed: int) -> bool:
    """True when the given seed is part of the active duty roster."""
    x = (seed * 2654435761) & 0xFFFFFFFF
    return x % SEED_MOD == 0


def emit_flare(seed: int) -> str:
    """What the flaky station prints for this seed (not always well-formed)."""
    base = base_token(seed)
    if (seed * (_audit(seed) % 13 + 1)) % RESYNC == 0:
        # mid-resync print: lower-cased head fragment -> violates uppercase rule
        return base[0:2].lower() + base[2:]
    return base


def is_well_formed(token: str) -> bool:
    return (
        len(token) == TOKEN_LEN
        and token.isupper()
        and token.startswith(PREFIX)
        and token.endswith(SUFFIX)
    )


def scan_roster() -> "list[int]":
    """Every commissioned seed in the full duty cycle range [0, _RANGE_HI)."""
    return [s for s in range(0, SEED_RANGE_HI) if commissioned(s)]
