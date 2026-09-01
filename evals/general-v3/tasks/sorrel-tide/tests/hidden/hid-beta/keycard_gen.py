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

* exactly 22 characters,
* only uppercase letters (A-Z) and decimal digits (0-9),
* begins with the fragment ``OBS``,
* ends with the fragment ``Z9``.

Vault selection
---------------
The vault pin unlocks for the unique well-formed keycard whose SHA-256 hex
digest, read as a base-16 integer, is congruent to ``VAULT_PIN`` modulo
``VAULT_MODULUS``.  Both constants are defined below and must be honored
exactly.
"""

SERIAL_HI = 3000
VAULT_PIN = 2
VAULT_MODULUS = 353

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
    return ((serial >> 2) % 8 == 3) != (sum(int(c) for c in str(serial)) % 9 == 5)


def emit_keycard(serial):
    """What the flaky station printer emits for ``serial`` (may be unusable)."""
    if not activated(serial):
        return None
    r = serial % 11
    body = _lcg_chars(serial, 17)
    if r == 0:
        # one character too many squeezed in before the suffix
        return "OBS" + body + body[-1] + "Z9"
    if r == 1:
        # lowercase body letter -> not the documented alphabet
        b = list(body)
        b[7] = b[7].lower()
        return "OBS" + "".join(b) + "Z9"
    if r == 2:
        # wrong prefix casing
        return "obs" + body + "Z9"
    if r == 3:
        # dash separator -> not the documented alphabet
        return "OBS" + body[:7] + "-" + body[7:] + "Z9"
    # r in 4..10: a genuinely well-formed keycard
    return "OBS" + body + "Z9"


def is_well_formed(tok):
    """The exact keycard format predicate (see module docstring)."""
    return (
        isinstance(tok, str)
        and len(tok) == 22
        and tok.startswith("OBS")
        and tok.endswith("Z9")
        and all(c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" for c in tok)
    )
