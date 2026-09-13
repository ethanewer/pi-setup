"""Reproducer for the empty-dict repr crash in scipy.optimize result objects.

Expected behaviour once the tree is repaired: prints a normal repr and exits 0.
At the buggy revision it crashes with:
    ValueError: max() iterable argument is empty
"""
from scipy.optimize import OptimizeResult

res = OptimizeResult(x=1, options={})
print(repr(res))