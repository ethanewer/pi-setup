#!/usr/bin/env python3
"""Hidden case A for skiff-beacon: a literal '+' immediately followed by two
hex digits, across many hex-letter/digit combinations, placements and mixed
percent-escapes, must stay literal when unquote_plus=False. The upstream
regression only covered '+00' and one timestamp; these inputs are new."""
import sys

from falcon.util import uri

CASES = [
    ('+00', False, '+00'),
    ('+0F', False, '+0F'),
    ('+0A', False, '+0A'),
    ('+10', False, '+10'),
    ('+A0', False, '+A0'),
    ('+fF', False, '+fF'),
    ('+2B', False, '+2B'),
    ('+2b', False, '+2b'),
    ('+9z', False, '+9z'),
    ('+z0', False, '+z0'),
    ('+000', False, '+000'),
    ('+0', False, '+0'),
    ('+', False, '+'),
    ('a+b', False, 'a+b'),
    ('a+b%2Bc', False, 'a+b+c'),
    ('%2B+00', False, '++00'),
    ('x+y+z', False, 'x+y+z'),
    ('total%20plus%2Btime', False, 'total plus+time'),
    ('+00', True, ' 00'),
    ('+0A', True, ' 0A'),
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

print(f'hidden case hex-adjacency: all {len(CASES)} cases passed')
sys.exit(0)