from gale.col import checksum, fetch


def test_sum_sequence():
    assert fetch(["n", "1", "n", "2", "n", "3", "a", "a"]) == 6


def test_empty_program():
    assert fetch([]) is None
    assert checksum(["n", "3", "a"]) == (ord("3") + ord("a") + ord("n")) % 97
