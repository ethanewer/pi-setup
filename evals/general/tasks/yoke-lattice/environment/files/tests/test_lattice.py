"""Tests for yoke.lattice — the grid model behind the CI demo repository."""

import pytest

from yoke.lattice import Grid, GridError


def test_parse_and_render_roundtrip():
    text = ".A.\nABA\n.A."
    grid = Grid.parse(text)
    assert grid.height == 3
    assert grid.width == 3
    assert grid.cell(1, 0) == "A"
    assert grid.cell(0, 0) == "."


def test_ragged_grid_rejected():
    with pytest.raises(GridError):
        Grid.parse(".A.\nABA\nA.")


def test_bad_tile_code_rejected():
    with pytest.raises(GridError):
        Grid.parse(".A.\nAB!\n.A.")


def test_empty_text_rejected():
    with pytest.raises(GridError):
        Grid.parse("\n\n\n")


def test_yokes_are_full_rows_of_one_code():
    grid = Grid.parse("AAA\n.A.\nBBB\n...")
    assert grid.yokes() == [(0, "A"), (2, "B")]


def test_blank_rows_are_not_yokes():
    grid = Grid.parse("...\n.A.\nAAA")
    assert grid.yokes() == [(2, "A")]


def test_transpose_swaps_dimensions():
    grid = Grid.parse(".A.\nABA")
    t = grid.transpose()
    assert (t.height, t.width) == (3, 2)
    for r in range(grid.height):
        for c in range(grid.width):
            assert t.cell(c, r) == grid.cell(r, c)
    assert t.cell(1, 0) == "A"


def test_flipped_mirrors_rows():
    grid = Grid.parse("ABC\nDEF")
    lines = grid.flipped().render().splitlines()
    assert lines[0] == "0|CBA"
    assert lines[1] == "1|FED"


def test_join_expands_nonempty_cells():
    base = Grid.parse("A.\n.A")
    tile = Grid.parse("BB\nBB")
    joined = base.join(tile, "B")
    assert (joined.height, joined.width) == (4, 4)
    assert joined.cell(0, 0) == "B"
    assert joined.cell(0, 1) == "B"
    assert joined.cell(0, 2) == "."
    assert joined.cell(3, 3) == "B"


def test_join_keeps_lattice_shape():
    base = Grid.parse("A\nA")
    tile = Grid.parse("X.X\nX.X")
    joined = base.join(tile, "X")
    assert (joined.height, joined.width) == (4, 3)
    assert joined.cell(1, 0) == "X"
    assert joined.cell(1, 1) == "."
    assert joined.cell(3, 2) == "X"


def test_equality_is_content_based():
    assert Grid.parse("A\nA") == Grid.parse("A\nA")
    assert Grid.parse("A\nA") != Grid.parse("A\nB")


def test_yoke_version_metadata():
    from yoke import __version__
    assert __version__.count(".") == 2