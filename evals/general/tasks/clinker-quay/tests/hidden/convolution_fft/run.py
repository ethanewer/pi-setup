"""Hidden case: convolution_fft on fresh integer triangles (independent).

Compare sympy.discrete.convolutions.convolution_fft against a naive
polynomial product computed inline. Fails while the tree is broken,
passes after the source fix.
"""
import sys

sys.path.insert(0, "/app/src")

from sympy.discrete.convolutions import convolution_fft  # noqa: E402


def naive_conv(a, b):
    out = [0] * (len(a) + len(b) - 1)
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            out[i + j] += x * y
    return out


def check(a, b):
    got = convolution_fft(a, b)
    want = naive_conv(a, b)
    ok = len(got) == len(want) and all(int(g) == w for g, w in zip(got, want))
    print(f"convolution_fft({a}, {b}) -> {'PASS' if ok else 'FAIL'}")
    if not ok:
        print(f"  got  = {list(got)}")
        print(f"  want = {want}")
    return ok


def main():
    r = [
        check([2, -1, 3, 0, 7, 4], [5, 6, -2, 1, 3]),
        check([1, 2], [3, 5, 8, 13]),
        check([7, 7, 7, 7, 7, 7, 7, 7], [1, 2, 3, 4, 5, 6, 7, 8]),
    ]
    return 0 if all(r) else 1


if __name__ == "__main__":
    sys.exit(main())