#!/bin/bash
# corbel-stave verifier.
#
# (A) falcon's own test modules for routing and middleware must pass on the
#     agent's fixed tree (they fail on the seeded regression).
# (B) the agent's WSGI app /app/app.py must serve the visible /app/routes.json
#     table, and
# (C) each hidden route table (registration-order ambiguity, complex-var
#     ambiguity, middleware ordering) must be served exactly per the contract,
#     verified over real HTTP on 127.0.0.1.
#
# Writes REWARD (0/1) to /logs/verifier/reward.txt. A verifier that raises
# before writing anything must still yield 0, so the EXIT trap covers that.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

# ---------------------------------------------------------------------------
# (A) upstream suite: the modules that exercise the router and middleware.
# ---------------------------------------------------------------------------
cd /app/src || { echo "FAIL: /app/src missing"; echo 0 > /logs/verifier/reward.txt; exit 0; }
UPSTREAM_MODULES="tests/test_uri_templates.py tests/test_uri_converters.py tests/test_compiled_router.py tests/test_default_router.py tests/test_middleware.py"
upstream_ok=0
if python -m pytest -p no:cacheprovider $UPSTREAM_MODULES -q > /tmp/cs_utests.out 2>&1; then
    echo "PASS [upstream] falcon routing/middleware modules green"
    upstream_ok=1
else
    echo "FAIL [upstream] falcon routing/middleware modules NOT green (seeded regression unfixed or fix incomplete)"
    tail -n 30 /tmp/cs_utests.out
fi

# ---------------------------------------------------------------------------
# WSGI launcher used for (B) and (C). Serves the deliverable /app/app.py with
# the given route table on 127.0.0.1:<ephemeral port>; writes the port to a
# file when ready.
# ---------------------------------------------------------------------------
cat > /tmp/cs_launcher.py <<'L'
import os
import sys
import wsgiref.simple_server

sys.path.insert(0, '/app')
os.environ['FALCON_ROUTES'] = sys.argv[1]
import app as shipped  # noqa: E402

assert hasattr(shipped, 'app'), '/app/app.py must define a module-level `app`'
httpd = wsgiref.simple_server.make_server('127.0.0.1', 0, shipped.app)
with open(sys.argv[2], 'w') as fh:
    fh.write(str(httpd.server_address[1]))
httpd.serve_forever()
L

# ---------------------------------------------------------------------------
# One case: start the app on $1 (routes.json), probe it with $2 (probes.json).
# Returns 0 iff every probe and the X-Chain/middleware contract hold.
# ---------------------------------------------------------------------------
probe_case() {
    local routes="$1" probes="$2"
    local port pid port_file=/tmp/cs_port.txt i rc
    rm -f "$port_file"
    FALCON_ROUTES="$routes" python3 /tmp/cs_launcher.py "$routes" "$port_file" &
    pid=$!
    i=0
    while [ ! -s "$port_file" ] && [ "$i" -lt 150 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    if [ ! -s "$port_file" ]; then
        echo "FAIL [app] WSGI server for $routes never became ready"
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        return 1
    fi
    port=$(cat "$port_file")
    python3 - "$port" "$probes" "$routes" <<'PY'
import json
import sys
import urllib.error
import urllib.request

port, probes_path, routes_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(routes_path) as fh:
    routes = json.load(fh)
with open(probes_path) as fh:
    probes = json.load(fh)['probes']

expected_chain = ', '.join(reversed(routes['middleware']))
failures = 0


def fetch(path):
    try:
        with urllib.request.urlopen(
            'http://127.0.0.1:%s%s' % (port, path), timeout=15
        ) as resp:
            return resp.status, resp.getheader('X-Chain'), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.getheader('X-Chain'), e.read()


for probe in probes:
    path = probe['path']
    status, chain, raw = fetch(path)
    if status != probe['status']:
        print('FAIL [app] %s: expected status %s, got %s' % (path, probe['status'], status))
        failures += 1
    if (chain or '') != expected_chain:
        print('FAIL [app] %s: X-Chain %r != expected %r' % (path, chain, expected_chain))
        failures += 1
    if probe['status'] == 200:
        try:
            body = json.loads(raw)
        except Exception as e:
            print('FAIL [app] %s: body not JSON: %s' % (path, e))
            failures += 1
            continue
        if body.get('label') != probe['label']:
            print('FAIL [app] %s: label %r != expected %r' % (path, body.get('label'), probe['label']))
            failures += 1
        if body.get('params') != probe['params']:
            print('FAIL [app] %s: params %r != expected %r' % (path, body.get('params'), probe['params']))
            failures += 1

print('CASE %s: %d probe failures' % (probes_path, failures))
sys.exit(1 if failures else 0)
PY
    rc=$?
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return "$rc"
}

# ---------------------------------------------------------------------------
# Run the cases: the visible fixture plus every hidden route table.
# ---------------------------------------------------------------------------
case_ok=0
if [ -f /app/app.py ] \
        && probe_case /app/routes.json /app/probes.json \
        && probe_case /tests/hidden/ambig-static-late/routes.json /tests/hidden/ambig-static-late/probes.json \
        && probe_case /tests/hidden/ambig-complex-order/routes.json /tests/hidden/ambig-complex-order/probes.json \
        && probe_case /tests/hidden/middleware-order/routes.json /tests/hidden/middleware-order/probes.json; then
    case_ok=1
fi

if [ "$upstream_ok" = 1 ] && [ "$case_ok" = 1 ]; then
    echo "REWARD 1: upstream suite green and app served all route tables per contract"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: upstream_suite=$upstream_ok app_cases=$case_ok"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0