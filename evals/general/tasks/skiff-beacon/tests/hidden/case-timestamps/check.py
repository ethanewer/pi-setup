#!/usr/bin/env python3
"""Hidden case B for skiff-beacon: realistic path segments and ISO-8601
timestamps carrying a UTC offset (e.g. +05:30, +00:00, +01:00) must decode
unchanged with unquote_plus=False, and plus/space semantics must hold with
unquote_plus=True. The upstream regression used a single timestamp shape;
these strings use other offsets, placements and mixed percent-escapes."""
import sys

from falcon.util import uri

CASES = [
    ('2024-08-15T12:34:56.789012+05:30', False,
     '2024-08-15T12:34:56.789012+05:30'),
    ('2026-06-29T23:11:38.964935+01:00.jpg', False,
     '2026-06-29T23:11:38.964935+01:00.jpg'),
    ('events/2025-03-01T00:00:00+00:00/export.gz', False,
     'events/2025-03-01T00:00:00+00:00/export.gz'),
    ('logs/node-7%2F%2B00:00.txt', False, 'logs/node-7/+00:00.txt'),
    ('a+b c%20d', False, 'a+b c d'),
    ('a+b', True, 'a b'),
    ('x%2By', False, 'x+y'),
    ('x%2By', True, 'x+y'),
    ('file+name+%2B+tag.txt', False, 'file+name+++tag.txt'),
    ('05:30+05:30', True, '05:30 05:30'),
]

fails = []
for encoded, unquote_plus, expected in CASES:
    actual = uri.decode(encoded, unquote_plus=unquote_plus)
    if actual != expected:
        fails.append((encoded, unquote_plus, expected, actual))
        print(f'CASE FAIL: decode({encoded!r}, unquote_plus={unquote_plus})'
              f' = {actual!r}, expected {expected!r}')

if fails:
    print(f'{len(fails)} of {len(CASES)} cases failed')
    sys.exit(1)

print(f'hidden case timestamps: all {len(CASES)} cases passed')
sys.exit(0)