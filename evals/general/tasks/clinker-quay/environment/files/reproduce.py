"""Reproducer for the clinker-quay regression.

SymPy's discrete Fourier-transform routines are compared against an
independent naive implementation. Run this from /app:

    python3 /app/reproduce.py

Exit code 0 means every check passes; exit code 1 means the tree is
unhealthy. The length-4 check passes even on the broken tree; the longer
checks fail (or crash) until the root cause is fixed.
"""
import cmath
import math
import sys

sys.path.insert(0, "/app/src")

from sympy.discrete import fft                              # noqa: E402
from sympy.discrete.convolutions import convolution_fft  # noqa: E402


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


def check_fft(seq, label):
    got = [complex(v.evalf(12)) for v in fft(list(seq))]
    want = naive_dft(list(seq))
    ok = len(got) == len(want) and all(abs(a - b) < 1e-6 for a, b in zip(got, want))
    print(f"[{label}] {'PASS' if ok else 'FAIL'}", flush=True)
    if not ok:
        print(f"    fft({list(seq)})", flush=True)
        print(f"    X[0] got = {got[0]}  want = {want[0]}", flush=True)
    return ok


def check_convolution(a, b):
    want = [0] * (len(a) + len(b) - 1)
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            want[i + j] += x * y
    got = convolution_fft(a, b)
    ok = len(got) == len(want) and all(int(g) == w for g, w in zip(got, want))
    print(f"[convolution_fft({a},{b})] {'PASS' if ok else 'FAIL'}", flush=True)
    return ok


def main():
    checks = [
        ("fft length 4 (passes even on the broken tree)",
         lambda: check_fft([1, 2, 3, 4], "fft length 4 (even broken tree)")),
        ("fft length 8", lambda: check_fft(list(range(1, 9)), "fft length 8")),
        ("fft length 9 (padded to 16)",
         lambda: check_fft([4, 1, 5, 9, 2, 6, 5, 3, 8], "fft length 9")),
        ("convolution_fft", lambda: check_convolution([1, 2, 3, 4, 5], [1, 3, 5, 7, 9])),
    ]
    results = []
    for label, fn in checks:
        try:
            results.append(fn())
        except Exception as exc:  # a broken tree can even crash the routine
            print(f"    {label} CRASHED: {type(exc).__name__}: {exc}", flush=True)
            results.append(False)

    if all(results):
        print("ALL CHECKS PASSED -- the tree is healthy.")
        return 0
    print("SOME CHECKS FAILED -- the tree has a regression in the discrete "
          "transforms. Localise, fix the source, and re-run.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())