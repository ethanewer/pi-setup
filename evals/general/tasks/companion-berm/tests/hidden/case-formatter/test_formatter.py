from cleo.io.null_io import NullIO

from poetry.puzzle.provider import Indicator


def test_formatter_holds_active_label_then_clears_after_error() -> None:
    indicator = Indicator(io=NullIO())
    assert indicator._formatter_context() == " "
    try:
        with Indicator.context() as set_context:
            set_context("downloading a dependency")
            assert "downloading a dependency" in indicator._formatter_context()
            raise RuntimeError("network error")
    except RuntimeError:
        pass
    assert Indicator.CONTEXT is None
    # the stale label must not be shown by the formatter on later lines
    assert "downloading a dependency" not in indicator._formatter_context()
    assert indicator._formatter_context() == " "


def test_formatter_clears_on_normal_exit() -> None:
    indicator = Indicator(io=NullIO())
    with Indicator.context() as set_context:
        set_context("resolving foo")
        assert "resolving foo" in indicator._formatter_context()
    assert "resolving foo" not in indicator._formatter_context()
    assert indicator._formatter_context() == " "
