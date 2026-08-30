"""Loomis Deep-Relay uplink keycard generator (do not modify).

This module deterministically derives uplink keycards from small integer
serial numbers.  Only serials on the active duty roster ever matter; the full
serial space ``[0, SERIAL_HI)`` is far larger than the roster and must never be
brute-forced token-by-token.

Contract
--------
``activated(serial)``   True iff ``serial`` is on the duty roster.
``emit_keycard(serial)`` what the flaky station printer emits for that serial;
                        the output is often NOT a usable keycard.
``is_well_formed(tok)`` the exact keycard format predicate.

A well-formed keycard satisfies ALL of:

* exactly 20 characters,
* only uppercase letters (A-Z) and decimal digits (0-9),
* begins with the fragment ``VLT``,
* ends with the fragment ``K7``.

Vault selection
---------------
The vault pin unlocks for the unique well-formed keycard whose SHA-256 hex
digest, read as a base-16 integer, is congruent to ``VAULT_PIN`` modulo
``VAULT_MODULUS``.  Both constants are defined below and must be honored
exactly.
"""

SERIAL_HI = 2048
VAULT_PIN = 87
VAULT_MODULUS = 251

_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789"


def _lcg_chars(seed, n):
    x = (seed * 1103515245 + 12345) % (2 ** 31)
    out = []
    for _ in range(n):
        x = (x * 1103515245 + 12345) % (2 ** 31)
        out.append(_ALPHABET[x % len(_ALPHABET)])
    return "".join(out)


def activated(serial):
    """Duty-roster gate: (decimal digit sum divisible by 7) XOR (serial % 5 == 2)."""
    if not isinstance(serial, int) or serial < 0 or serial >= SERIAL_HI:
        return False
    return (sum(int(c) for c in str(serial)) % 7 == 0) != (serial % 5 == 2)


def emit_keycard(serial):
    """What the flaky station printer emits for ``serial`` (may be unusable)."""
    if not activated(serial):
        return None
    r = serial % 11
    body = _lcg_chars(serial, 15)
    if r == 0:
        # one character too many squeezed in before the suffix
        return "VLT" + body + body[-1] + "K7"
    if r == 1:
        # lowercase body letter -> not the documented alphabet
        b = list(body)
        b[7] = b[7].lower()
        return "VLT" + "".join(b) + "K7"
    if r == 2:
        # wrong prefix casing
        return "vLT" + body + "K7"
    if r == 3:
        # dash separator -> not the documented alphabet
        return "VLT" + body[:7] + "-" + body[7:] + "K7"
    # r in 4..10: a genuinely well-formed keycard
    return "VLT" + body + "K7"


def is_well_formed(tok):
    """The exact keycard format predicate (see module docstring)."""
    return (
        isinstance(tok, str)
        and len(tok) == 20
        and tok.startswith("VLT")
        and tok.endswith("K7")
        and all(c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" for c in tok)
    )
