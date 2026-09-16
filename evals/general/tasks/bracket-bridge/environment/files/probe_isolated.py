#!/usr/bin/env python3
"""Isolated source-fidelity probe for bracket-bridge.

Runs with `python3 -S` (no site-packages, no .pth import hooks) under
PYTHONPATH=/app/src, so the falcon code exercised here is exactly the
checked-out source in the deliverable tree — an import-time shim in
site-packages cannot touch this interpreter.

Asserts the full behaviour contract of the task with plain asserts:

  * scope without a 'client' field: the documented no-peer fallback
  * scope with 'client': None: the same fallback, no exception (THE bug)
  * 'client' None combined with proxy headers: header chain plus fallback
  * a real client address: completely unchanged behaviour
  * end-to-end: a real falcon.asgi.App reached through simulate_get with a
    null client, and with a normal client

Exit status is 0 iff every assertion holds.
"""
import sys

import falcon
import falcon.asgi
from falcon import testing
from falcon.asgi import Request

_MISSING = object()


def make_req(headers=None, client=_MISSING):
    scope = testing.create_scope(headers=headers)
    if client is not _MISSING:
        scope['client'] = client
    return Request(scope, None)


def check(label, cond):
    if not cond:
        print('FAIL: {0}'.format(label), file=sys.stderr)
        raise SystemExit(1)
    print('ok: {0}'.format(label))


# 1. pre-existing behaviour: no 'client' field at all.
req = make_req()
check('no client field: remote_addr', req.remote_addr == '127.0.0.1')
check('no client field: access_route', req.access_route == ['127.0.0.1'])

# 2. THE bug: 'client' explicitly None must fall back, not crash.
req = make_req(client=None)
check('null client: remote_addr', req.remote_addr == '127.0.0.1')
check('null client: access_route', req.access_route == ['127.0.0.1'])

# 3. null client combined with proxy headers.
req = make_req(headers={'X-Forwarded-For': '203.0.113.197'}, client=None)
check('null client + XFF: access_route',
      req.access_route == ['203.0.113.197', '127.0.0.1'])
check('null client + XFF: remote_addr', req.remote_addr == '127.0.0.1')

req = make_req(headers={'X-Real-IP': '10.1.2.3'}, client=None)
check('null client + X-Real-IP: access_route',
      req.access_route == ['10.1.2.3', '127.0.0.1'])
check('null client + X-Real-IP: remote_addr', req.remote_addr == '127.0.0.1')

# 4. real client address: unchanged.
req = make_req(headers={'X-Forwarded-For': '203.0.113.197'},
               client=('198.51.100.2', 54321))
check('real client + XFF: access_route',
      req.access_route == ['203.0.113.197', '198.51.100.2'])
check('real client + XFF: remote_addr', req.remote_addr == '198.51.100.2')


# 5. end-to-end through a real ASGI app.
class RemoteEcho:
    async def on_get(self, req, resp):
        resp.status = falcon.HTTP_200
        resp.media = {
            'remote_addr': req.remote_addr,
            'access_route': req.access_route,
        }


app = falcon.asgi.App()
app.add_route('/echo', RemoteEcho())

result = testing.simulate_get(app, '/echo', extras={'client': None})
check('e2e null client', result.status_code == 200 and result.json == {
    'remote_addr': '127.0.0.1',
    'access_route': ['127.0.0.1'],
})

result = testing.simulate_get(app, '/echo', remote_addr='198.51.100.2')
check('e2e real client',
      result.status_code == 200 and result.json == {
          'remote_addr': '198.51.100.2',
          'access_route': ['198.51.100.2'],
      })

print('ALL ISOLATED PROBES PASSED')