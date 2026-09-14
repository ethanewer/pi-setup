"""Hidden case 2: direct assertions on the Content-Type header parser --
valueless parameters must be dropped, valid parameters must survive."""
import pytest

from requests.utils import _parse_content_type_header


def test_valueless_param_dropped():
    assert _parse_content_type_header("text/html; charset") == ("text/html", {})


def test_valueless_param_among_valid_dropped():
    assert _parse_content_type_header(
        "multipart/form-data; boundary=abc; no_equals"
    ) == ("multipart/form-data", {"boundary": "abc"})


def test_no_boolean_placeholders_survive():
    content_type, params = _parse_content_type_header("text/plain; a; b; c=d")
    assert content_type == "text/plain"
    assert params == {"c": "d"}
    assert all(not isinstance(value, bool) for value in params.values())


def test_quoted_values_and_spacing_still_work():
    assert _parse_content_type_header(
        'text/html; charset="utf-8"; foo'
    ) == ("text/html", {"charset": "utf-8"})
    assert _parse_content_type_header(
        "multipart/form-data; boundary = something"
    ) == ("multipart/form-data", {"boundary": "something"})


def test_empty_and_blank_segments_tolerated():
    assert _parse_content_type_header("application/json ; ; ") == (
        "application/json",
        {},
    )
    assert _parse_content_type_header("text/html;") == ("text/html", {})


def test_parameter_keys_lowercased():
    assert _parse_content_type_header(
        "application/json ; Charset = utf-8 ; boundary2='x' "
    ) == ("application/json", {"charset": "utf-8", "boundary2": "x"})