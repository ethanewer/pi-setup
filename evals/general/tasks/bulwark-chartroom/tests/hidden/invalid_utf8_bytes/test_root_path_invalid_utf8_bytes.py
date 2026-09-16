# Hidden case 4 for bulwark-chartroom: a non-ASCII SCRIPT_NAME whose bytes
# do NOT form valid UTF-8 when re-encoded (lone 0xA9). The correct behaviour
# (matching the upstream fix's PEP 3333 handling) is a U+FFFD replacement,
# not a crash and not a pass-through of the raw latin-1 glyphs.
# The upstream regression test never exercises invalid byte sequences.
import falcon.testing as testing
from falcon import Request


def test_root_path_invalid_utf8_bytes():
    env = testing.create_environ()
    env['SCRIPT_NAME'] = '/caf\xa9'  # 0xA9 is not a valid UTF-8 start byte
    req = Request(env)
    assert req.root_path == '/caf\ufffd', repr(req.root_path)