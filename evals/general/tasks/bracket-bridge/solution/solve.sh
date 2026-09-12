#!/bin/bash
# Oracle for bracket-bridge: applies the upstream fix (fall back to
# 127.0.0.1 when the ASGI connection scope's 'client' field is None, exactly
# as when it is missing) to the falcon checkout at /app/src, then proves it
# with the probe and the project's own regression test.
set -e

python3 /solution/fix_request_asgi.py

echo "== probe output after the fix =="
python3 /app/probe_scope_client.py

echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/test_request_asgi.py::test_client_none_in_scope -q -p no:cacheprovider

echo "== own ASGI request slice =="
python3 -m pytest tests/asgi/test_request_asgi.py tests/asgi/test_request_context_asgi.py tests/asgi/test_misc.py -q -p no:cacheprovider