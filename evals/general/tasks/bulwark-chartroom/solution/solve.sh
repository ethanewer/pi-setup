#!/bin/bash
# Oracle for bulwark-chartroom: writes the conforming reproduction, applies
# the real upstream fix to the falcon checkout at /app/src, and re-runs both
# the reproduction and the upstream regression test (extracted into
# /opt/golden at image build time) to prove the task is passable.
set -euo pipefail

# 1. Apply the fix to the working tree.
python3 /solution/fix_request.py /app/src/falcon/request.py

# 2. Deliver the reproduction (per the contract in the instruction).
cat > /app/repro.py <<'PY'
from falcon import testing, Request

PREFIX = "/caf\u00e9"  # the app is mounted under this non-ASCII prefix

env = testing.create_environ()
# A PEP 3333 WSGI server hands the mount prefix to the app with its UTF-8
# bytes re-decoded one code point at a time (the latin-1 "tunnel").
env["SCRIPT_NAME"] = PREFIX.encode().decode("iso-8859-1")
req = Request(env)
observed = req.root_path
print("observed root_path:", repr(observed))
if observed == PREFIX:
    print("OK: root path is the correctly decoded prefix")
    raise SystemExit(0)
print("BUG: reported root path is mojibake, expected", repr(PREFIX))
raise SystemExit(1)
PY
chmod 644 /app/repro.py

# 3. Prove it: repro must pass, the upstream regression test must pass.
echo "== reproduction on the fixed tree =="
python3 /app/repro.py
echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/test_root_path_non_ascii_wsgi.py -q -p no:cacheprovider

echo "== project's own request-attributes suite =="
python3 -m pytest tests/test_request_attrs.py -q -p no:cacheprovider
echo "ORACLE OK"