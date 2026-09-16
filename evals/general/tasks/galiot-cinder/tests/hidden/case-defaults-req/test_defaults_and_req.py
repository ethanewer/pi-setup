"""Hidden case for galiot-cinder: defaults, create_req() and Request.

RAW_URI must be the raw request path in every entry point built on
create_environ(); the '/' default keeps its value, a Request built from the
environ must see the decoded path independently of the raw URI, and the
ISO-8859-1 tunnelling of decoded UTF-8 must be untouched.
"""
import falcon.request
import falcon.testing as testing


def test_hidden_c_root_default_keeps_slash():
    env = testing.create_environ()
    assert env['RAW_URI'] == '/'
    assert env['PATH_INFO'] == '/'


def test_hidden_c_create_req_raw_and_decoded_paths_diverge():
    req = testing.create_req(path='/d%C3%A9p%C3%B4t/x%2Fy')
    assert req.env['RAW_URI'] == '/d%C3%A9p%C3%B4t/x%2Fy'
    assert req.env['PATH_INFO'] == '/d\u00c3\u00a9p\u00c3\u00b4t/x/y'
    assert req.path == '/d\u00e9p\u00f4t/x/y'


def test_hidden_c_percent_encoded_utf8_passthrough():
    # RAW_URI keeps the raw percent-encoded form; PATH_INFO tunnels the
    # decoded UTF-8 through ISO-8859-1 exactly as before any fix.
    raw = '/%E3%83%86%E3%82%B9%E3%83%88'
    env = testing.create_environ(path=raw)
    assert env['RAW_URI'] == raw, (raw, env['RAW_URI'])
    assert env['PATH_INFO'] == '/\u30c6\u30b9\u30c8'.encode('utf-8').decode('iso-8859-1')
    assert falcon.request.Request(env).path == '/\u30c6\u30b9\u30c8'