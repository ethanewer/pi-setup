"""Regression test-suite for the /issue session header CWE-93 boundary.

Run:  python3 -m pytest /app -q
"""
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
from wsgiref.simple_server import make_server

sys.path.insert(0, '/app')

import service  # noqa: E402
from service import cookies  # noqa: E402


def _wrap(value, flag='strict'):
    return cookies.build(value, flag)


def test_normal_cookie_still_works():
    v = _wrap('uid=alice&ttl=1800', 'strict')
    assert v.startswith('uid=alice&ttl=1800;') and 'HttpOnly' in v


def test_no_crlf_ever_into_header_value():
    for bad in ('a\r\nSet-Cookie: evil=1', 'b\nX-Auth: yes', 'c\r\n\r\nExtra: x'):
        v = _wrap(bad, 'strict')
        assert '\r' not in v and '\n' not in v, ('CRLF leaked', bad, v)


def test_sanitized_value_preserves_normal_text():
    v = _wrap('uid=alice;ttl=60', 'strict')
    assert 'uid=alice' in v


_SRV = None
_PORT = None


def _start():
    global _SRV, _PORT
    _SRV = make_server('127.0.0.1', 0, service.app())
    _PORT = _SRV.server_address[1]
    threading.Thread(target=_SRV.serve_forever, daemon=True).start()


def _stop():
    if _SRV is not None:
        _SRV.shutdown()


def _fetch(path):
    try:
        with urllib.request.urlopen('http://127.0.0.1:%d%s' % (_PORT, path), timeout=5) as r:
            return r.headers.get_all('Set-Cookie') or [], False
    except urllib.error.HTTPError as e:
        return e.headers.get_all('Set-Cookie') or [], False
    except Exception:
        return [], True


def test_live_endpoint_no_injection():
    _start()
    try:
        ok, raised = _fetch('/issue?token=alice')
        assert not raised and ok and len(ok) >= 1
        assert all('alice' in c for c in ok)

        evil = urllib.parse.quote('x%0D%0ASet-Cookie: session=hijacked')
        cookies_list, raised = _fetch('/issue?token=%s' % evil)
        assert not raised, 'CRLF injection still corrupts the response'
        for c in cookies_list:
            assert '\r' not in c and '\n' not in c
        assert not any((c or '').startswith('session=hijacked') for c in cookies_list), \
            'injected hijacked header still present'
    finally:
        _stop()