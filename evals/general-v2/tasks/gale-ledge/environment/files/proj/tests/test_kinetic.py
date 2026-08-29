import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))


def test_identity_compose():
    from gale.kinetic import compose
    r, names = compose([("eye", [1, 0, 0, 1])])
    assert r == [1, 0, 0, 1]
    assert names == "eye"


def test_empty_compose_is_identity():
    from gale.kinetic import compose
    r, names = compose([])
    assert r == [1, 0, 0, 1]
    assert names == "identity"


def test_two_matrix_forward_order():
    from gale.kinetic import compose, matmul
    A = [1, 2, 3, 4]
    B = [5, 6, 7, 8]
    r, names = compose([("a", A), ("b", B)])
    assert names == "a|b"
    assert r == [19, 22, 43, 50]
    assert r == matmul(A, B)


def test_three_matrix_forward_order():
    from gale.kinetic import compose, matmul
    A = [1, 2, 3, 4]
    B = [0, 1, 1, 0]
    C = [2, 0, 0, 2]
    r, names = compose([("a", A), ("b", B), ("c", C)])
    expect = matmul(matmul(A, B), C)
    assert names == "a|b|c"
    assert r == expect == [4, 2, 8, 6]