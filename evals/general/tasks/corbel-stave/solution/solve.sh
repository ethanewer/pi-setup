#!/bin/bash
# corbel-stave oracle: (1) restore the routing-regression seed by putting the
# per-level node ordering (literal > complex-var > simple-var) back into
# falcon's compiled router, and (2) author the contract-compliant WSGI app at
# /app/app.py, then smoke-check both. Never reads /tests.
set -eu

# ---- 1. Fix the framework: restore the deterministic node ordering the seed
# removed. This is the real source fix; it makes route resolution independent
# of registration order, which is falcon's documented contract.
python3 - <<'PY'
path = '/app/src/falcon/routing/compiled.py'
with open(path, encoding='utf-8') as fh:
    src = fh.read()

anchor = (
    '        # NOTE(kgriffs & philiptzou): Sort nodes in this sequence:\n'
    '        # static nodes(0), complex var nodes(1) and simple var nodes(2).\n'
    '        # so that none of them get masked.\n'
)
restored = anchor + (
    '        nodes = sorted(\n'
    '            nodes, key=lambda node: node.is_var + (node.is_var and not node.is_complex)\n'
    '        )\n'
)

assert anchor in src, 'router ordering anchor not found; source differs from seed'
assert 'nodes = sorted(' not in src, 'router ordering already present; seed not applied'
with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src.replace(anchor, restored))
print('fixed: falcon/routing/compiled.py node ordering restored')
PY

# ---- 2. Write the deliverable WSGI app per the contract in instruction.md.
cat > /app/app.py <<'PY'
"""Contract-compliant falcon WSGI app driven by a JSON route table.

The table path comes from $FALCON_ROUTES (default /app/routes.json). See
instruction.md: echo matched routes as JSON, 404 for unmatched paths, and
stamp X-Chain with the middleware names in reverse registration order.
"""

import json
import os

import falcon


class EchoResource:
    def __init__(self, label):
        self._label = label

    def on_get(self, req, resp, **params):
        resp.media = {'label': self._label, 'params': params}


class ChainStamp:
    """Append this middleware's name to X-Chain.

    falcon invokes process_response in reverse registration order, so the
    header ends up in reverse table order, as the contract requires.
    """

    def __init__(self, name):
        self._name = name

    def process_request(self, req, resp):
        pass

    def process_response(self, req, resp, resource, req_succeeded):
        current = resp.get_header('X-Chain') or ''
        if current:
            current += ', '
        resp.set_header('X-Chain', current + self._name)


def _load_table():
    path = os.environ.get('FALCON_ROUTES', '/app/routes.json')
    with open(path) as fh:
        return json.load(fh)


_table = _load_table()
app = falcon.App(middleware=[ChainStamp(name) for name in _table['middleware']])
for entry in _table['routes']:
    app.add_route(entry['template'], EchoResource(entry['label']))
PY

# ---- 3. Smoke-check: upstream modules green and the app serves correctly.
cd /app/src
python -m pytest -p no:cacheprovider \
    tests/test_uri_templates.py tests/test_uri_converters.py \
    tests/test_compiled_router.py tests/test_default_router.py \
    tests/test_middleware.py -q >/tmp/cs_oracle_pytest.out 2>&1
tail -n 2 /tmp/cs_oracle_pytest.out

python3 - <<'PY'
import json
import os
import sys

sys.path.insert(0, '/app')
os.environ['FALCON_ROUTES'] = '/app/routes.json'
import app as ship

# Drive the app through falcon's WSGI test client (offline, no port needed).
from falcon import testing  # noqa: E402

client = testing.TestClient(ship.app)
checks = [
    ('/v1/items/special', 200, 'special', {}),
    ('/v1/items/42', 200, 'item', {'item_id': '42'}),
    ('/v1/orders/7', 200, 'order', {'oid': 7}),
    ('/v1/unknown', 404, None, None),
]
for path, want_status, want_label, want_params in checks:
    res = client.simulate_get(path)
    assert res.status_code == want_status, (path, res.status_code)
    if want_status == 200:
        body = res.json
        assert body['label'] == want_label, (path, body)
        assert body['params'] == want_params, (path, body)
    # X-Chain must be the middleware names in reverse registration order.
    assert res.headers.get('X-Chain') == 'beta, alpha', (path, res.headers.get('X-Chain'))
print('app smoke check: OK')
PY

echo "oracle done -> fixed /app/src/falcon/routing/compiled.py, wrote /app/app.py"