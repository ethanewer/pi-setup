from gale.col import checksum, fetch


def test_add():
    assert fetch(["n", "3", "n", "4", "a"]) == 7


def test_dup():
    assert fetch(["n", "2", "d"]) == 2


def test_swap():
    assert fetch(["n", "1", "n", "2", "s"]) == 1
