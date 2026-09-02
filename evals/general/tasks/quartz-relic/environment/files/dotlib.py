"""dotlib — loose, frozen reference implementation of the scalar product.

This module is legacy scaffolding left at the repository root by a former
maintainer.  It is FROZEN: it must remain byte-identical.  The product team
has decided that the importable package ``dotkit`` must be self-contained
and must NOT import this module (the package has to survive being copied
out of the repository on its own).
"""


def dot(a, b):
    """Return the scalar (dot) product of two numeric sequences.

    - ``a`` and ``b`` are sequences (list or tuple) of ints/floats.
    - Mismatched lengths raise ``ValueError``.
    - Two empty sequences yield ``0``.
    - Inputs are never mutated.
    """
    if len(a) != len(b):
        raise ValueError(
            "scalar product requires equal-length sequences "
            "(got %d and %d)" % (len(a), len(b))
        )
    total = 0
    for x, y in zip(a, b):
        total = total + x * y
    return total
