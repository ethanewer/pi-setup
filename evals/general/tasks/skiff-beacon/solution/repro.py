#!/usr/bin/env python3
"""Reproduction for the falcon URI-decoding defect (skiff-beacon).

Decoding with plus-to-space conversion disabled ('unquote_plus=False') must
leave a literal '+' untouched, even when the character immediately after it
is a hex digit; instead the accelerated decoder treats '+XX' as a percent
escape and replaces the '+' with the decoded byte. This asserts the correct
behaviour and exits non-zero while the defect is present.

The script imports falcon from the environment (PYTHONPATH) and hardcodes no
filesystem paths, so the verifier can run it against two falcon trees that
differ only in PYTHONPATH: the pristine pre-fix checkout (this script must
fail there) and the repaired tree (it must pass there).
"""
import sys

from falcon.util import uri

CASES = [
    ('+00', False, '+00'),
    ('2026-06-29T23:11:38.964935+00:00.jpg', False,
     '2026-06-29T23:11:38.964935+00:00.jpg'),
]

failures = []
for encoded, unquote_plus, expected in CASES:
    actual = uri.decode(encoded, unquote_plus=unquote_plus)
    if actual != expected:
        failures.append((encoded, unquote_plus, actual, expected))

if failures:
    for encoded, unquote_plus, actual, expected in failures:
        print(f'BUG PRESENT: decode({encoded!r}, unquote_plus={unquote_plus})'
              f' = {actual!r}, expected {expected!r}')
    sys.exit(1)

print('ok: decode preserves a literal plus when unquote_plus is disabled')
sys.exit(0)