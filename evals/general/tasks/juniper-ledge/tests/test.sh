#!/usr/bin/env bash
# Verifier for juniper-ledge.
# Re-runs the live /app deliverables against a running instance of the vault
# service and checks real HTTP behaviour. Always writes a numeric reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
PASS=1
fail() { echo "FAIL: $*"; PASS=0; }
BASE="http://127.0.0.1:8743"
APP_PID=""

# Reuse the service if an agent already has it up; otherwise start it.
if ! curl -sf "$BASE/api/v1/announce" -o /dev/null 2>/dev/null; then
  (cd /app && python3 -m juniper_app.app >/tmp/vault.log 2>&1) &
  APP_PID=$!
  trap 'kill "$APP_PID" 2>/dev/null' EXIT TERM INT
  up=0
  for i in $(seq 1 60); do
    if curl -sf "$BASE/api/v1/announce" -o /dev/null 2>/dev/null; then up=1; break; fi
    sleep 0.25
  done
  if [ "$up" != "1" ]; then
    echo "FAIL: service would not start"; echo 0 > /logs/verifier/reward.txt; exit 0
  fi
fi

# ---- 0. deliverables exist ----
for f in audit_report.md ssti_locations.json login_session.py admin_result.json post_payload.py; do
  if [ ! -f "/app/$f" ]; then fail "missing deliverable /app/$f"; fi
done

# ---- 1. audit_report.md flags BOTH injection points ------------------------
if ! python3 - /app/audit_report.md <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read().lower()
ok = True
def need(tag, sub):
    global ok
    if sub not in s:
        ok = False; print("  audit missing:", tag)
need("SQL injection", "concatenat")
need("SQL query", "select")
need("auth file", "ledgelib/auth.py")
need("render file", "ledgelib/rendering.py")
need("SSTI sink", "from_string")
sys.exit(0 if ok else 1)
PY
then
  fail "audit_report.md did not flag both injection points"
fi

# ---- 2. ssti_locations.json names the rendering sink ----------------------
if ! python3 - /app/ssti_locations.json <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
j = json.loads(raw)
ser = json.dumps(j)
if "rendering.py" not in ser or "from_string" not in ser:
    print("  ssti_locations.json must mention rendering.py and from_string")
    sys.exit(1)
PY
then
  fail "ssti_locations.json does not reference the rendering sink"
fi

# ---- 3. login_session.py -> admin session, real DB retire -----------------
if ! python3 /app/login_session.py >/tmp/login.out 2>/tmp/login.err; then
  fail "login_session.py exited non-zero"
  sed 's/^/    /' /tmp/login.err | head -5
else
  grep -q "admin_session ok" /tmp/login.out || fail "login_session.py did not print 'admin_session ok'"
  if ! python3 - /app/admin_result.json <<'PY'
import json, sqlite3, sys
j = json.loads(open(sys.argv[1], encoding="utf-8").read())
if j.get("role") != "admin":
    print("  admin_result.json role != admin"); sys.exit(1)
if not isinstance(j.get("ledgers"), list) or len(j["ledgers"]) < 1:
    print("  admin_result.json ledgers not a populated list"); sys.exit(1)
r = j.get("retired")
if not isinstance(r, dict) or r.get("id") != 27 or r.get("status") != "retired":
    print("  admin_result.json retired != retired ledger 27"); sys.exit(1)
st = sqlite3.connect("/app/juniper_app/vault.db").execute(
    "SELECT status FROM ledger WHERE id=27").fetchone()[0]
if st != "retired":
    print("  DB shows ledger 27 was not retired by the admin call"); sys.exit(1)
PY
  then
    fail "admin_result.json does not reflect a real admin session"
  fi
fi

# ---- 4. admin gate rejects a forged token --------------------------------
code=$(curl -s -o /dev/null -w '%{http_code}' -H "X-Vault-Token: deadbeef" "$BASE/api/v1/ledgers")
if [ "$code" != "403" ]; then fail "admin gate not enforced (got HTTP $code for forged token)"; fi

# ---- 5. rendezvous payloads ------------------------------------------------
expect_motto() {
  python3 -c "import hashlib;seed=$1*7+3;d=hashlib.sha256(('capital:'+str(seed)).encode()).hexdigest();print('threshold-'+d[:8])"
}

run_success() {
  want=$(expect_motto "$1")
  out=$(python3 /app/post_payload.py "$1" 2>/dev/null)
  if [ "$out" != "$want" ]; then fail "post_payload($1): got '${out:-""}' want '$want'"; fi
}

run_negative() {
  out=$(python3 /app/post_payload.py "$1" 2>/tmp/pp.err)
  rc=$?
  if [ "$rc" -eq 0 ]; then fail "post_payload($1): should exit non-zero"; fi
  if printf '%s' "$out" | grep -q "threshold-"; then fail "post_payload($1): printed a final string on failure"; fi
}

# visible success: ledger 27 (retired during the admin flow)
run_success 27

# hidden cases
for dir in /tests/hidden/*/; do
  [ -d "$dir" ] || continue
  mode=$(cat "$dir/mode" 2>/dev/null)
  arg=$(cat "$dir/arg" 2>/dev/null)
  if [ "$mode" = "success" ]; then
    run_success "$arg"
  elif [ "$mode" = "fail" ]; then
    run_negative "$arg"
  else
    fail "hidden $dir: invalid mode '${mode:-}'"
  fi
done

# ---- reward ---------------------------------------------------------------
[ "$PASS" -eq 1 ] && reward=1
if [ "$reward" -eq 1 ]; then echo REWARD=1; else echo REWARD=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0