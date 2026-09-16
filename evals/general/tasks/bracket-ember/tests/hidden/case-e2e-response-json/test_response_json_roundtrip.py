"""Hidden case for bracket-ember: the full Response.json() error path.

The upstream regression test constructs requests.exceptions.JSONDecodeError
directly. This case drives the real user-visible path: a Response with an
invalid JSON body whose .json() raises the exception. requests wraps the
stdlib json.JSONDecodeError raised by its decoder into
requests.exceptions.JSONDecodeError; the wrapped instance must then survive a
pickle round-trip with msg/doc/pos and repr intact.
"""

import json
import pickle

import pytest

import requests
from requests.exceptions import JSONDecodeError

INVALID_BODIES = [
    b'{"responseCode":["706"],"data":null}{"responseCode":["706"],"data":null}',
    b"[1, 2, ",
    b'{"a": 1, "b": }',
    '{"\u043a\u043b\u044e\u0447": }'.encode("utf-8"),
]


def _response_with(body: bytes) -> requests.Response:
    resp = requests.Response()
    resp.status_code = 200
    resp.encoding = "utf-8"  # pin the plain decode path
    resp._content = body
    return resp


@pytest.mark.parametrize("body", INVALID_BODIES)
def test_response_json_raises_the_expected_requests_error(body):
    with pytest.raises(JSONDecodeError) as excinfo:
        _response_with(body).json()
    err = excinfo.value
    # The wrapper must carry exactly the stdlib decoder's diagnosis.
    with pytest.raises(json.JSONDecodeError) as ref_info:
        json.loads(body.decode("utf-8"))
    ref = ref_info.value
    assert err.msg == ref.msg
    assert err.doc == ref.doc
    assert err.pos == ref.pos
    # It is both a requests error and a stdlib json error (IOError and
    # json.JSONDecodeError are both in its inheritance chain).
    assert isinstance(err, json.JSONDecodeError)
    assert isinstance(err, OSError)


@pytest.mark.parametrize("body", INVALID_BODIES)
def test_response_json_error_roundtrips_through_pickle(body):
    try:
        _response_with(body).json()
    except JSONDecodeError as err:
        caught = err
    else:
        pytest.fail("Response.json() did not raise")
    back = pickle.loads(pickle.dumps(caught))
    assert repr(back) == repr(caught)
    assert back.msg == caught.msg
    assert back.doc == caught.doc
    assert back.pos == caught.pos