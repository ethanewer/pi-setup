import pytest

from poetry.puzzle.provider import Indicator


def test_normal_exit_still_clears() -> None:
    with Indicator.context() as set_context:
        set_context("package-foo")
        assert Indicator.CONTEXT == "package-foo"
    assert Indicator.CONTEXT is None


def test_reenter_after_exception() -> None:
    try:
        with Indicator.context() as set_context:
            set_context("first-operation")
            raise RuntimeError()
    except RuntimeError:
        pass
    assert Indicator.CONTEXT is None
    # a subsequent, unrelated block must start with a clean label
    with Indicator.context() as set_context:
        set_context("second-operation")
        assert Indicator.CONTEXT == "second-operation"
    assert Indicator.CONTEXT is None


def test_label_changes_within_block_then_aborts() -> None:
    with pytest.raises(KeyError):
        with Indicator.context() as set_context:
            set_context("old-label")
            set_context("new-label")
            assert Indicator.CONTEXT == "new-label"
            raise KeyError("gone")
    assert Indicator.CONTEXT is None
