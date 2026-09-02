#!/usr/bin/env python3
"""Grove exact-expression synth.

usage: expr.py <spec.json>

spec.json: {"nums": [ints], "target": int}
Produces an arithmetic expression using each number exactly once and only
+ - * / and parentheses that evaluates EXACTLY to the target (rational math).
Prints the expression to stdout.
"""
import json
import sys
from fractions import Fraction
from itertools import permutations


def search(nums, target):
    n = len(nums)
    ops = ["+", "-", "*", "/"]

    def evals(frag):
        """All (value, string) results for a list of value/str pairs."""
        if len(frag) == 1:
            return [(frag[0][0], frag[0][1])]
        out = []
        for split in range(1, len(frag)):
            left = evals(frag[:split])
            right = evals(frag[split:])
            for (lv, ls), (rv, rs) in ((a, b) for a in left for b in right):
                for op in ops:
                    if op == "+":
                        out.append((lv + rv, "(%s + %s)" % (ls, rs)))
                    elif op == "-":
                        out.append((lv - rv, "(%s - %s)" % (ls, rs)))
                    elif op == "*":
                        out.append((lv * rv, "(%s * %s)" % (ls, rs)))
                    elif op == "/":
                        if rv != 0:
                            out.append((lv / rv, "(%s / %s)" % (ls, rs)))
        return out

    for perm in permutations(nums):
        frag = [(Fraction(v), str(v)) for v in perm]
        for val, s in evals(frag):
            if val == target:
                return s
    return None


def main() -> int:
    with open(sys.argv[1]) as fh:
        spec = json.load(fh)
    s = search([int(v) for v in spec["nums"]], Fraction(spec["target"]))
    if s is None:
        print("UNSOLVABLE")
        return 1
    print(s)
    return 0


if __name__ == "__main__":
    sys.exit(main())