# Hidden case 1 for bulwark-chartroom: a Cyrillic mount prefix, where every
# character is multi-byte in UTF-8 (12 UTF-8 bytes for 6 characters). The
# upstream regression test only covers the single accented letter '/café'.
import falcon.testing as testing
from falcon import Request


def test_root_path_cyrillic_prefix():
    prefix = '/\u043f\u0440\u043e\u0434\u0430\u0436\u0438'  # /продажи
    env = testing.create_environ()
    env['SCRIPT_NAME'] = prefix.encode().decode('iso-8859-1')
    req = Request(env)
    assert req.root_path == prefix, repr(req.root_path)