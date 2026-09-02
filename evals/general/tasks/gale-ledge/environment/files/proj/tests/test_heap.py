import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))


def test_sweep_full_recycle_boundary():
    from gale import heap as hp
    a = hp.Arena([0, 0, 0, 0, 0])
    runs = a.sweep()
    assert runs == [[0, 5]], runs
    assert hp.reclaimed_cells(a) == 5
    assert a.contiguous(5) == 5


def test_sweep_mixed_run_lengths():
    from gale import heap as hp
    a = hp.Arena([1, 0, 0, 0, 0, 1, 0, 0])
    a.sweep()
    assert hp.reclaimed_cells(a) == 6
    assert a.contiguous(3) == 4  # free runs [1,4] and [6,2]


def test_sweep_interior_and_boundary_runs():
    from gale import heap as hp
    a = hp.Arena([1, 0, 1, 0, 0, 0, 0])
    runs = a.sweep()
    assert runs == [[1, 1], [3, 4]], runs
    assert a.contiguous(4) == 4


def test_full_recycle_from_partial():
    from gale import heap as hp
    a = hp.Arena([1, 0, 0, 1, 0])
    a.cells = [0] * 5
    a.sweep()
    assert a.contiguous(5) == 5