#!/bin/bash
#
# Verifier for vine-ledge.
# Boots from pristine and:
#   A. requires /app/provision.sh (executable) and /app/requirements.lock
#   B. runs /app/provision.sh (idempotent) to build the workspace
#   C. checks both named venvs exist and import
#   D. checks chain-query/Flask/requests import in the serve venv, requests in
#      the ingest venv, and the gRPC toolchain imports SYSTEM-WIDE
#   E. checks the pinned torch/transformers toolchain is fully preserved and
#      the offline load path still works
#   F. checks /app/requirements.lock matches the installed versions
#   G. checks the Jupyter server on :8899 and the chain-query HTTP API on
#      :8123 are alive, then verifies the visible and every hidden /height case
#
# Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
ok=1
fail(){ echo "FIELD: $*"; ok=0; }

# ---------- A. deliverables ----------
[ -f /app/provision.sh ]   || fail "missing /app/provision.sh"
[ -x /app/provision.sh ]   || fail "/app/provision.sh is not executable"
[ -f /app/requirements.lock ] || fail "missing /app/requirements.lock"

if [ ! -x /app/provision.sh ]; then
  echo "$ok" > /logs/verifier/reward.txt
  exit 0
fi

# ---------- B. run the deliverable (idempotent re-run) ----------
if ! bash /app/provision.sh >/tmp/prov.log 2>&1; then
  fail "provision.sh exited non-zero; log tail:"; tail -5 /tmp/prov.log | sed 's/^/    /' >&2
fi

# ---------- C. both named venvs exist and run ----------
for v in ingest serve; do
  [ -x "/app/venvs/$v/bin/python" ] || fail "venv $v missing (no /app/venvs/$v/bin/python)"
done

# ---------- D. imports + exact versions ----------
/app/venvs/serve/bin/python - <<'PY' || fail "serve venv: chainquery/flask/requests import or version"
import importlib.metadata as md
import chainquery, flask, requests
assert chainquery.__version__ == "1.2.0", ("chainquery", chainquery.__version__)
assert md.version("flask") == "3.1.3", ("flask", md.version("flask"))
assert md.version("requests") == "2.34.2", ("requests", md.version("requests"))
PY
/app/venvs/ingest/bin/python -c "import requests" || fail "ingest venv: requests not importable"

python3 - <<'PY' || fail "gRPC toolchain not importable system-wide / wrong version"
import grpc, grpc_tools, google.protobuf
import importlib.metadata as md
assert md.version("grpcio") == "1.83.0", ("grpcio", md.version("grpcio"))
assert md.version("grpcio-tools") == "1.83.0", ("grpcio-tools", md.version("grpcio-tools"))
assert md.version("protobuf") == "7.36.0", ("protobuf", md.version("protobuf"))
PY

# ---------- E. pinned ML toolchain preserved ----------
python3 /app/offline_load.py || fail "offline load path/pinned torch+transformers altered"
python3 - <<'PY' || fail "torch/transformers drifted from pinned baseline"
import importlib.metadata as md
assert md.version("torch") == "2.13.0", ("torch", md.version("torch"))
assert md.version("transformers") == "5.16.1", ("transformers", md.version("transformers"))
PY

# ---------- F. requirements.lock matches installed set ----------
python3 - <<'PY' || fail "requirements.lock inconsistent with installed packages"
import importlib.metadata as md
import re, subprocess


def ver(interp, pkg):
    out = subprocess.run(
        [interp, "-c", "import importlib.metadata as m; print(m.version(%r))" % pkg],
        capture_output=True, text=True)
    return out.stdout.strip()


pins = {}
with open("/app/requirements.lock") as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^(\S+?)(?:==)(\S+)$", line)
        if m:
            pins[m.group(1)] = m.group(2)

sys_map = ["grpcio", "grpcio-tools", "protobuf", "notebook", "torch", "transformers"]
serve_map = ["flask", "requests", "chainquery"]
for n in sys_map + serve_map:
    assert n in pins, f"{n} not declared in requirements.lock"
    interp = "python3" if n in sys_map else "/app/venvs/serve/bin/python"
    v = ver(interp, n)
    assert v == pins[n], (n, v, pins[n])
PY

# ---------- G. background services up ----------
wait_up() { # $1=port $2=name
  local port="$1" name="$2" i
  for i in $(seq 1 60); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      exec 3>&- 3<&- 2>/dev/null || true
      return 0
    fi
    sleep 1
  done
  fail "$name not listening on :$port"
  return 1
}
wait_up 8123 "chain-query HTTP API" || true
wait_up 8899 "jupyter notebook server" || true

http_case() { # $1=url_path_query  $2=expected_json  $3=label
  python3 - "$1" "$2" "$3" <<'PY' || { fail "case $3: HTTP/JSON mismatch"; return 1; }
import json, sys, urllib.request, urllib.parse
url, exp_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
exp = json.load(open(exp_path))
expect_code = 400 if "error" in exp else 200
try:
    with urllib.request.urlopen("http://127.0.0.1:8123/" + url, timeout=10) as r:
        code = r.getcode()
        body = json.load(r)
except urllib.error.HTTPError as e:
    code = e.code
    body = json.load(e)
assert code == expect_code, (label, code, expect_code)
assert body == exp, (label, body, exp)
PY
}

# health endpoint answers
python3 - <<'PY' || fail "health endpoint not answering"
import json, urllib.request
with urllib.request.urlopen("http://127.0.0.1:8123/health", timeout=10) as r:
    assert r.getcode() == 200
    assert json.load(r) == {"status": "ok"}
PY

# visible sample
http_case "height?hash=$(printf 'a%.0s' {1..64})" /tests/expected.json visible

# hidden cases
if [ -d /tests/hidden ]; then
  for h in /tests/hidden/*.hash; do
    [ -e "$h" ] || continue
    exp="${h%.hash}.expected.json"
    [ -f "$exp" ] || continue
    q=$(python3 -c "import sys,urllib.parse;print(urllib.parse.quote(open(sys.argv[1]).read()))" "$h")
    http_case "height?hash=$q" "$exp" "$(basename "$h")"
  done
fi

# ---------- reward ----------
[ "$ok" -eq 1 ] && reward=1 || reward=0
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
