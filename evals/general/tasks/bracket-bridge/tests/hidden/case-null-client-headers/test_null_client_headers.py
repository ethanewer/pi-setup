"""Hidden case for bracket-bridge: null client combined with proxy headers.

The upstream regression test only covers a bare Request whose scope has
'client': None and no proxy headers. This case drives the same
access_route code path with X-Forwarded-For and X-Real-IP headers present:
the fallback '127.0.0.1' client must be appended to the address chain
instead of crashing during the scope unpack, and the pre-existing
missing-key fallback must keep working.
"""

from falcon import testing
from falcon.asgi import Request

_MISSING = object()


def _req(headers=None, client=_MISSING):
    scope = testing.create_scope(headers=headers)
    if client is not _MISSING:
        scope['client'] = client
    # recv is never called for these properties; None matches how a real
    # server hands the scope to the request object.
    return Request(scope, None)


def test_x_forwarded_for_with_null_client():
    req = _req(headers={'X-Forwarded-For': '203.0.113.197'}, client=None)
    assert req.access_route == ['203.0.113.197', '127.0.0.1']
    assert req.remote_addr == '127.0.0.1'


def test_x_real_ip_with_null_client():
    req = _req(headers={'X-Real-IP': '10.1.2.3'}, client=None)
    assert req.access_route == ['10.1.2.3', '127.0.0.1']
    assert req.remote_addr == '127.0.0.1'


def test_missing_client_key_still_falls_back():
    # Regression guard: the pre-existing KeyError path (no 'client' key at
    # all) must keep producing the same fallback after the fix.
    req = _req()
    assert req.access_route == ['127.0.0.1']
    assert req.remote_addr == '127.0.0.1'


def test_normal_client_with_proxy_header():
    # Guard: a real client address is still appended after the header chain,
    # and remote_addr reflects the closest known address.
    req = _req(headers={'X-Forwarded-For': '203.0.113.197'}, client=('198.51.100.2', 54321))
    assert req.access_route == ['203.0.113.197', '198.51.100.2']
    assert req.remote_addr == '198.51.100.2'