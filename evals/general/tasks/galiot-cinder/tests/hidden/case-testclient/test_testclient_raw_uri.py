"""Hidden case for galiot-cinder: the user-visible symptom through TestClient.

An application that hands the raw URI to downstream logic (routing, signing,
cache keys) must observe the same RAW_URI under falcon.testing.TestClient as
under a real WSGI server (wsgiref, gunicorn, uWSGI): the raw, still
percent-encoded path while PATH_INFO carries the decoded path. These cases
drive a real app end to end, which the upstream regression test does not.
"""
import falcon
import falcon.testing as testing


def _make_probe(probe):
    class ProbeResource:
        def on_get(self, req, resp, **params):
            probe['env'] = {
                'RAW_URI': req.env.get('RAW_URI'),
                'PATH_INFO': req.env.get('PATH_INFO'),
                'QUERY_STRING': req.env.get('QUERY_STRING'),
            }
            resp.text = 'ok'

    return ProbeResource()


def test_hidden_b_testclient_reports_raw_uri_like_a_real_server():
    probe = {}
    app = falcon.App()
    app.add_sink(_make_probe(probe).on_get, '/v1/items')

    client = testing.TestClient(app)
    result = client.simulate_get('/v1/items/a%2Fb', query_string='page=2')

    assert result.status_code == 200, result.status_code
    assert probe['env'] == {
        'RAW_URI': '/v1/items/a%2Fb',
        'PATH_INFO': '/v1/items/a/b',
        'QUERY_STRING': 'page=2',
    }


def test_hidden_b_encoded_utf8_field_through_testclient():
    probe = {}
    app = falcon.App()
    app.add_route('/caf/{dish}', _make_probe(probe))

    client = testing.TestClient(app)
    result = client.simulate_get('/caf/men%C3%BC')

    assert result.status_code == 200, result.status_code
    assert probe['env']['RAW_URI'] == '/caf/men%C3%BC'
    assert probe['env']['PATH_INFO'] == '/caf/men\u00c3\u00bc'