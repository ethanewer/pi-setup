"""Hidden case: fft correctness on other lengths/inputs (independent DFT).

Exercises the same code path as the visible reproducer but with fresh
sequences: FAILS while the tree is broken, PASSes once the root cause is
repaired at the source.
"""
import cmath
import math
import sys

sys.path.insert(0, "/app/src")

from sympy.discrete import fft  # noqa: E402


def naive_dft(x):
    # sympy's sympy.discrete.fft (a) uses exp(+2*pi*i*k*i/n) --- the conjugate
    # of the textbook convention --- and (b) pads the sequence with zeros up
    # to the next power of two before transforming. The reference mimics both.
    m = 1
    while m < len(x):
        m *= 2
    x = list(x) + [0] * (m - len(x))
    n = m
    return [sum(x[k] * cmath.exp(2j * math.pi * i * k / n) for k in range(n))
            for i in range(n)]


def check(seq):
    got = [complex(v.evalf(12)) for v in fft(list(seq))]
    want = naive_dft(list(seq))
    maxerr = max((abs(a - b) for a, b in zip(got, want)), default=0.0)
    ok = len(got) == len(want) and all(abs(a - b) < 1e-6 for a, b in zip(got, want))
    print(f"fft len={len(seq)} maxerr={maxerr:.2e} {'PASS' if ok else 'FAIL'}")
    return ok


def main():
    r = [
        # not the same sequence as the visible reproducer
        check([-3, 11, 5, -7, 0, 2, 13, -1]),
        check([2, -6, 18, -54, 162, -486, 1458, -4374, 13122]),
        check([1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597]),
    ]
    return 0 if all(r) else 1


if __name__ == "__main__":
    sys.exit(main())