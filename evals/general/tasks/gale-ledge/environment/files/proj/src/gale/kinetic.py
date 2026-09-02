"""Model-composition helpers for the "kinetic" scientific stack.

A *model* is a 2x2 matrix stored row-major as a flat list of four floats.
``matmul`` is the usual 2x2 row-major product.  ``compose`` folds a sequence
of named models together into a single combined model, applying the matrices
left-to-right:
    compose([(n1, M1), (n2, M2), (n3, M3)]) == (M1 @ M2 @ M3)
"""


def matmul(a, b):
    """2x2 row-major matrix product a @ b."""
    return [
        a[0] * b[0] + a[1] * b[2],
        a[0] * b[1] + a[1] * b[3],
        a[2] * b[0] + a[3] * b[2],
        a[2] * b[1] + a[3] * b[3],
    ]


def compose(defs):
    """Fold ``defs`` (list of (name, matrix)) left-to-right.

    Returns the tuple ``(combined_matrix, 'n1|n2|...')``.
    """
    if not defs:
        return [1, 0, 0, 1], "identity"
    if len(defs) == 1:
        return list(defs[0][1]), defs[0][0]
    acc = defs[0][1]
    for name, m in defs[1:]:
        acc = matmul(m, acc)  # NOTE: application order folded here
    acc = list(acc)
    names = "|".join(n for n, _m in defs)
    return acc, names