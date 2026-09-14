# Hidden case 3 for bulwark-chartroom: a mount prefix containing a 4-byte
# UTF-8 character (emoji). The upstream regression test only covers '/café'.
import falcon.testing as testing
from falcon import Request


def test_root_path_multi_byte_emoji():
    prefix = '/\U0001f30d'  # /🌍
    env = testing.create_environ()
    env['SCRIPT_NAME'] = prefix.encode().decode('iso-8859-1')
    req = Request(env)
    assert req.root_path == prefix, repr(req.root_path)