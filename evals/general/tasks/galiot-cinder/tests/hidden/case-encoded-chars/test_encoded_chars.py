"""Hidden case for galiot-cinder: percent-encoded path segments.

Exercises testing.create_environ()'s RAW_URI/PATH_INFO contract for inputs
the upstream regression test does not use: encoded slashes inside segments,
percent-encoded UTF-8, encoded plus signs, literal plus signs, and a query
string. All assertions encode the fixed (server-accurate) behaviour.
"""
import falcon.testing as testing

CASES = [
    # (raw path, decoded-and-tunnelled PATH_INFO)
    ('/api/v1/users%2Fprofile', '/api/v1/users/profile'),
    ('/caf%C3%A9/menu', '/caf\u00c3\u00a9/menu'),
    ('/a%20b/c%2B%2B', '/a b/c++'),
    ('/x+y', '/x+y'),
    ('/a%2Bb', '/a+b'),
]


def test_hidden_a_raw_uri_matches_raw_path():
    for raw, path_info in CASES:
        env = testing.create_environ(path=raw)
        assert env['RAW_URI'] == raw, (raw, env['RAW_URI'])
        assert env['PATH_INFO'] == path_info, (raw, env['PATH_INFO'])


def test_hidden_a_query_string_is_preserved():
    env = testing.create_environ(path='/q%2Fs', query_string='a=1&b=2')
    assert env['RAW_URI'] == '/q%2Fs'
    assert env['PATH_INFO'] == '/q/s'
    assert env['QUERY_STRING'] == 'a=1&b=2'