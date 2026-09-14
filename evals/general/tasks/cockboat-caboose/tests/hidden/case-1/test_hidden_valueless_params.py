"""Hidden case 1: valueless Content-Type parameters through
get_encoding_from_headers -- inputs the upstream regression test does not use."""
import pytest

from requests.structures import CaseInsensitiveDict
from requests.utils import get_encoding_from_headers


def enc(headers):
    return get_encoding_from_headers(CaseInsensitiveDict(headers))


def test_valueless_charset_text_html():
    assert enc({"content-type": "text/html; charset"}) == "ISO-8859-1"


def test_valueless_charset_text_plain():
    assert enc({"content-type": "text/plain; charset"}) == "ISO-8859-1"


def test_valueless_param_before_valid_boundary():
    # valueless parameter precedes a valid one
    assert enc({"content-type": "text/html; charset; boundary=xyz"}) == "ISO-8859-1"


def test_valueless_param_after_valid_boundary():
    # valueless parameter follows a valid one
    assert enc({"content-type": "text/html; boundary=xyz; charset"}) == "ISO-8859-1"


def test_valueless_charset_application_json():
    assert enc({"content-type": "application/json; charset"}) == "utf-8"


def test_valueless_only_params_non_text():
    # many valueless params, non-text media type: no encoding, no crash
    assert enc({"content-type": "image/png; foo; bar; baz"}) is None


def test_valueless_in_realistic_header_set():
    h = {
        "content-type": "text/html; charset",
        "server": "nginx",
        "transfer-encoding": "chunked",
    }
    assert enc(h) == "ISO-8859-1"