"""Hidden case 3: encoding resolution with mixed valueless/valued parameters
and edge-value charsets -- inputs upstream does not use."""
import pytest

from requests.structures import CaseInsensitiveDict
from requests.utils import get_encoding_from_headers


def enc(headers):
    return get_encoding_from_headers(CaseInsensitiveDict(headers))


def test_valid_charset_among_valueless_params():
    assert enc({"content-type": "text/html; foo; charset=UTF-8"}) == "UTF-8"


def test_quoted_charset_among_valueless_params():
    assert enc({"content-type": 'text/html; charset="windows-1252"'}) == "windows-1252"


def test_empty_charset_value_unchanged():
    # 'charset=' has an equals sign and an empty value: it is recorded
    # (as before), the stripped result is the empty string, no crash.
    assert enc({"content-type": "text/html; charset="}) == ""


def test_capitalized_content_type_header():
    assert enc({"Content-Type": "text/html; charset"}) == "ISO-8859-1"
    assert enc({"CONTENT-TYPE": "text/html; charset"}) == "ISO-8859-1"