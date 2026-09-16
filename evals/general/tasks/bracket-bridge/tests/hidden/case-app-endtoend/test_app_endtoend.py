"""Hidden case for bracket-bridge: end-to-end app with a null client.

The upstream regression test constructs a Request object directly. This
case drives a real falcon.asgi.App through falcon.testing.simulate_get with
extras={'client': None}, so the whole pipeline (app lifecycle, routing,
responder) sees a connection scope whose client field is None. A normal
client address is asserted unchanged as a guard.
"""

import falcon
import falcon.asgi
import falcon.testing as testing


class RemoteEcho:
    async def on_get(self, req, resp):
        resp.status = falcon.HTTP_200
        resp.media = {
            'remote_addr': req.remote_addr,
            'access_route': req.access_route,
        }


app = falcon.asgi.App()
app.add_route('/echo', RemoteEcho())


def test_null_client_via_app_pipeline():
    result = testing.simulate_get(app, '/echo', extras={'client': None})
    assert result.status_code == 200
    assert result.json == {
        'remote_addr': '127.0.0.1',
        'access_route': ['127.0.0.1'],
    }


def test_normal_client_unchanged():
    result = testing.simulate_get(app, '/echo', remote_addr='198.51.100.2')
    assert result.status_code == 200
    assert result.json == {
        'remote_addr': '198.51.100.2',
        'access_route': ['198.51.100.2'],
    }