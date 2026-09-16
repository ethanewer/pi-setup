"""Hidden case 1: single Forwarded headers whose value ends with an empty or
malformed element, in forms the upstream regression test does not use
(upstream uses 'a', '; a', 'for=1.2.3.4; a', 'for=_real; x',
'bad; for=_real'). Every one of these hangs forever at the buggy revision;
at the fixed revision the read must terminate immediately and keep only the
valid leading element.
"""

import pytest
from multidict import CIMultiDict

from aiohttp.test_utils import make_mocked_request

CASES = [
    ("for=1.2.3.4; ;a", {"for": "1.2.3.4"}),        # two separators in a row
    ("for=_real;x", {"for": "_real"}),              # no space after the ';'
    ("for=_real; \t", {"for": "_real"}),            # trailing whitespace after ';'
    ('for="a;b"; somebody', {"for": "a;b"}),        # quoted value hides a ';'
    ("for=1.2.3.4; ; ; a", {"for": "1.2.3.4"}),     # run of empty elements
]


@pytest.mark.parametrize("header, expected", CASES)
def test_trailing_malformed_value_terminates_and_parses(
    header: str, expected: dict
) -> None:
    req = make_mocked_request("GET", "/", headers=CIMultiDict({"Forwarded": header}))
    assert dict(req.forwarded[0]) == expected