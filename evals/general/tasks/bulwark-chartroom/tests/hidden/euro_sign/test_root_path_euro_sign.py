# Hidden case 2 for bulwark-chartroom: a mount prefix consisting of a single
# 3-byte UTF-8 character (EURO SIGN). The upstream regression test only
# covers '/café' (a 2-byte character).
import falcon.testing as testing
from falcon import Request


def test_root_path_euro_sign():
    prefix = '/\u20ac'  # /€
    env = testing.create_environ()
    env['SCRIPT_NAME'] = prefix.encode().decode('iso-8859-1')
    req = Request(env)
    assert req.root_path == prefix, repr(req.root_path)