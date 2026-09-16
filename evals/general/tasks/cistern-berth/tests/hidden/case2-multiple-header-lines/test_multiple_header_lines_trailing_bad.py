"""Hidden case 2: several Forwarded header lines on one request, where a
line carries a trailing empty/malformed element. Reading request.forwarded
must parse every line and terminate; at the buggy revision the first such
line hangs the parse loop forever (the upstream regression test only ever
builds requests with a single header line and a single element).
"""

from multidict import CIMultiDict

from aiohttp.test_utils import make_mocked_request


def test_valid_line_after_bad_line() -> None:
    headers = CIMultiDict()
    headers.add("Forwarded", "for=1.2.3.4; ;a")
    headers.add("Forwarded", "for=_real")
    req = make_mocked_request("GET", "/", headers=headers)
    assert [dict(e) for e in req.forwarded] == [
        {"for": "1.2.3.4"},
        {"for": "_real"},
    ]


def test_bad_line_after_valid_line() -> None:
    headers = CIMultiDict()
    headers.add("Forwarded", "for=_real")
    headers.add("Forwarded", "for=9.9.9.9; x")
    req = make_mocked_request("GET", "/", headers=headers)
    assert [dict(e) for e in req.forwarded] == [
        {"for": "_real"},
        {"for": "9.9.9.9"},
    ]


def test_several_pairs_then_bad_tail() -> None:
    headers = CIMultiDict()
    headers.add("Forwarded", "for=_one; for=_two; z")
    headers.add("Forwarded", "for=_three")
    req = make_mocked_request("GET", "/", headers=headers)
    assert [dict(e) for e in req.forwarded] == [
        {"for": "_two"},
        {"for": "_three"},
    ]