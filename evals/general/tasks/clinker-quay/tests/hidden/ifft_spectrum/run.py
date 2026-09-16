"""Hidden case: inverse transform round-trip from an independent spectrum.

Build a spectrum with a plain naive DFT, then require sympy's ifft to
recover the sequence. Exercises the same butterfly as the visible
reproducer, in the inverse direction, on different numeric inputs.
"""
import cmath
import math
import sys

sys.path.insert(0, "/app/src")

from sympy.discrete import ifft  # noqa: E402


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
    n = len(seq)
    spec = naive_dft(seq)                     # independent spectrum, padded
    got = [complex(v.evalf(12)) for v in ifft(spec)]
    padded = seq + [0] * (len(got) - n)
    ok = len(got) == len(spec) and all(abs(a - b) < 1e-6 for a, b in zip(got, padded))
    maxerr = max((abs(a - b) for a, b in zip(got, padded)), default=0.0)
    print(f"ifft roundtrip len={n} maxerr={maxerr:.2e} {'PASS' if ok else 'FAIL'}")
    return ok


def main():
    r = [
        check([0.5, -1.5, 2.25, -3.75, 4.5, -5.25, 6.0, -7.5]),
        check([1, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0]),
        check([3.3, 1.1, 4.4, 1.5, 9.9, 2.2, 6.6, 5.5]),
    ]
    return 0 if all(r) else 1


if __name__ == "__main__":
    sys.exit(main())