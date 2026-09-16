"""Hidden case: the fix must not change the accepted semantics of any VALID
marker syntax. These lines parse at the pinned commit and must still parse
after the fix.
"""
import pytest

from pip._internal.req.constructors import install_req_from_line

EXACT_MARKERS = [
    ("baz; python_version == \"3.12\"", 'python_version == "3.12"'),
    # a semicolon inside the quoted marker value is legal
    ('semicolon; os_name == "a; b"', 'os_name == "a; b"'),
    ('ne; python_version != "3.10"', 'python_version != "3.10"'),
]


@pytest.mark.parametrize(("line", "expected"), EXACT_MARKERS)
def test_valid_marker_string_preserved(line: str, expected: str) -> None:
    req = install_req_from_line(line)
    assert str(req.markers) == expected


def test_marker_expression_with_and_or_parses() -> None:
    line = 'pipe; python_version >= "3.12" and extra == "x"'
    req = install_req_from_line(line)
    assert req.markers is not None


def test_empty_marker_section_still_legal() -> None:
    # a trailing semicolon with nothing after it is an empty marker section
    req = install_req_from_line("trailing; ")
    assert req.markers is None