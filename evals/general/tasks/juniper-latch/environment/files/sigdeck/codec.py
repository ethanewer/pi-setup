"""Decode helpers for raw telemetry tokens.

A raw token is the 16-bit two's-complement pattern of a signed sample,
written as a hex literal with an optional `0x`/`0X` prefix (1-4 hex digits).
Examples: `0x0004` -> 4, `0xFFFE` -> -2, `0x0100` -> 256, `1A` -> 26.
"""

_HEX_DIGITS = set("0123456789abcdef")


def decode(token):
    """Return the signed 16-bit sample encoded by `token` (an int in
    [-32768, 32767]). Raises ValueError for anything that is not 1-4 hex
    digits (the `0x` prefix optional, surrounding whitespace tolerated)."""
    s = str(token).strip().lower()
    if s.startswith("0x"):
        s = s[2:]
    if not (1 <= len(s) <= 4) or any(c not in _HEX_DIGITS for c in s):
        raise ValueError("malformed sample token: %r" % (token,))
    v = int(s, 16)
    if v >= 0x8000:
        v -= 0x10000
    return v
