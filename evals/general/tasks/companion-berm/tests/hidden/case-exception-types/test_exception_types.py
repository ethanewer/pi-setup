import pytest

from poetry.puzzle.provider import Indicator


class CustomOperationError(Exception):
    pass


@pytest.mark.parametrize(
    "exc",
    [
        ValueError,
        KeyError,
        RuntimeError,
        CustomOperationError,
    ],
)
def test_context_clears_after_various_exceptions(exc: type[BaseException]) -> None:
    with pytest.raises(exc):
        with Indicator.context() as set_context:
            set_context("artifact-42")
            assert Indicator.CONTEXT == "artifact-42"
            raise exc("boom")
    assert Indicator.CONTEXT is None
