"""Regression test for the /login Set-Cookie header-injection boundary.

Run with:  python3 /app/regression_check.py

Before the security fix this test FAILS: CRLF bytes in the `user` query
parameter inject an extra Set-Cookie response header. After the smallest safe
patch (make build_session_cookie() produce a single header-line value) both the
unit-level boundary check and the live WSGI integration check pass.
"""
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
from wsgiref.simple_server import make_server

sys.path.insert(0, '/app')
import main  # noqa: E402

FAILURES = []


def check_no_crlf(value, where):
    if value is None:
        FAILURES.append('no Set-Cookie header at %s' % where)
        return
    if '\r' in value or '\n' in value:
        FAILURES.append('CRLF present in Set-Cookie header value at %s: %r' % (where, value))


def get_cookies(port, path):
    """Return (set-cookie-header-list, raised_flag)."""
    try:
        with urllib.request.urlopen('http://127.0.0.1:%d%s' % (port, path), timeout=10) as r:
            return r.headers.get_all('Set-Cookie') or [], False
    except urllib.error.HTTPError as e:
        return e.headers.get_all('Set-Cookie') or [], False
    except Exception as e:
        FAILURES.append('http error for %s: %r' % (path, e))
        return [], True


def run_checks():
    # --- unit-level boundary check -----------------------------------------
    val = main.build_session_cookie('alice', 'admin')
    if not val.startswith('session=alice;'):
        FAILURES.append('cookie format changed unexpectedly: %r' % val)
    for bad in ('evil\r\nSet-Cookie: owner=admin',
                'evil\nX-Injected: yes',
                'a\r\n\r\nExtraHeader: x'):
        check_no_crlf(main.build_session_cookie(bad, 'guest'), 'build_session_cookie(%r)' % bad)

    # --- live integration check -------------------------------------------
    srv = make_server('127.0.0.1', 0, main.app)
    port = srv.server_address[1]
    th = threading.Thread(target=srv.serve_forever, daemon=True)
    th.start()
    try:
        cookies, raised = get_cookies(port, '/login?user=alice&role=admin')
        if not raised:
            if not cookies:
                FAILURES.append('normal request returned no Set-Cookie header')
            for c in cookies:
                check_no_crlf(c, 'normal')

        evil = urllib.parse.quote('mallory\r\nSet-Cookie: session=hijacked')
        cookies, raised = get_cookies(port, '/login?user=' + evil)
        for c in (cookies or []):
            check_no_crlf(c, 'attack')
        if any((c or '').startswith('session=hijacked') for c in cookies):
            FAILURES.append('CRLF injection succeeded: extra hijacked Set-Cookie emitted')
    finally:
        srv.shutdown()


if __name__ == '__main__':
    run_checks()
    if FAILURES:
        print('REGRESSION FAIL')
        for f in FAILURES:
            print('  -', f)
        sys.exit(1)
    print('REGRESSION OK')