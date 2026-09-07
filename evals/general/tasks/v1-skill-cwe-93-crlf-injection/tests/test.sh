#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/safe_cookie.txt ]; then
  if python3 - <<'PYEOF'
import importlib.util
spec = importlib.util.spec_from_file_location("cwe", "/app/cwe.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
san = m.sanitize
for t in ["a\r\nb", "x\x0d\x0aSet-Cookie: admin=1", "evil\revil\nz", "\r\n", "plain"]:
    out = san(t)
    assert '\r' not in out and '\n' not in out, (t, out)
got = open('/app/safe_cookie.txt', encoding='latin-1').read()
assert '\r' not in got and '\n' not in got, got
assert got.startswith('session=aliceSet-Cookie: admin=true'), got
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt