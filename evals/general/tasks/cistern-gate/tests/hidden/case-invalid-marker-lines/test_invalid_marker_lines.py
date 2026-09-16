"""Hidden case: invalid marker sections on requirement lines must surface as a
clean InstallationError naming the requirement, never as an internal
pip._vendor.packaging.markers.InvalidMarker traceback.

Inputs deliberately differ from the upstream regression test for this bug
(which uses 'name; python_version == "1"; python_version == "2"').
"""
import pytest

from pip._internal.exceptions import InstallationError
from pip._internal.req.constructors import install_req_from_line

INVALID_LINES = [
    # two marker expressions separated by a semicolon
    'pkg; extra == "a"; python_version > "3.12"',
    # marker string with an unterminated quote
    "foo; python_version == '3",
    # marker string with an unbalanced parenthesis
    'bar; (python_version == "3.10"',
    # two semicolon-separated markers on a requirement with extras
    'pkg[extra]; extra == "a"; extra == "b"',
]


@pytest.mark.parametrize("line", INVALID_LINES)
def test_invalid_marker_line_raises_installation_error(line: str) -> None:
    with pytest.raises(InstallationError) as excinfo:
        install_req_from_line(line)
    assert "Invalid requirement" in excinfo.value.args[0]


def test_invalid_marker_is_not_leaked_as_invalidmarker() -> None:
    """The vendored InvalidMarker must never escape install_req_from_line."""
    from pip._vendor.packaging.markers import InvalidMarker

    for line in INVALID_LINES:
        with pytest.raises(Exception) as excinfo:
            install_req_from_line(line)
        assert isinstance(excinfo.value, InstallationError)
        assert not isinstance(excinfo.value, InvalidMarker)