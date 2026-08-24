#!/usr/bin/env python3
"""Provided evaluator: checks the decoded out.dat against the run table.

It prints a targeted mismatch datum (indices/byte counts only, not the full
expected stream) and exits non-zero when the decode is not correct.
"""
import sys

RUNS = [(3, 0x41), (160, 0x42), (2, 0x43), (130, 0x44),
        (1, 0x45), (255, 0x21), (1, 0x46)]

want = b''
for n, v in RUNS:
    want += bytes([v]) * n

try:
    with open('out.dat', 'rb') as f:
        out = f.read()
except FileNotFoundError:
    print('VERIFY FAIL: out.dat missing')
    sys.exit(1)

ok = (out == want)
print('VERIFY OK len=%d' % len(want) if ok else
      'VERIFY FAIL out_len=%d want_len=%d' % (len(out), len(want)))
if not ok:
    n = min(len(out), len(want))
    idx = next((i for i in range(n) if out[i] != want[i]), n)
    print('first mismatch at byte %d' % idx)
sys.exit(0 if ok else 1)