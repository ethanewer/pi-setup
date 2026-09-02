#!/bin/bash
# Verifier for spume-ferry. Starts the kiosk service if needed, re-runs the
# live /app/claim_pass.py deliverable against it (visible + hidden dock ids),
# checks the deliverable files, and confirms negative behaviour on closed /
# invalid dock ids. Always writes a numeric reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
PASS=1
fail() { echo "FAIL: $*"; PASS=0; }
BASE="http://127.0.0.1:8652"
APP_PID=""

# Reuse the service if an agent already has it up; otherwise start it.
if ! curl -sf "$BASE/api/v1/announce" -o /dev/null 2>/dev/null; then
  (cd /app && python3 -m ferry_app.app >/tmp/ferry_verify.log 2>&1) &
  APP_PID=$!
  trap 'kill "$APP_PID" 2>/dev/null' EXIT TERM INT
  up=0
  for i in $(seq 1 60); do
    if curl -sf "$BASE/api/v1/announce" -o /dev/null 2>/dev/null; then up=1; break; fi
    sleep 0.25
  done
  if [ "$up" != "1" ]; then
    echo "FAIL: service would not start"
    echo 0 > /logs/verifier/reward.txt
    exit 0
  fi
fi

# ---- 0. deliverables exist ----
for f in claim_pass.py final_message.txt claim_receipt.json; do
  [ -f "/app/$f" ] || fail "missing deliverable /app/$f"
done
[ -x /app/claim_pass.py ] || fail "/app/claim_pass.py is not executable"

# ---- shared expectation helper (documented formula, mirrors the service) ----
expect_for() {
  python3 - "$1" <<'PY'
import hashlib, sys
d = int(sys.argv[1])
nonce = (d * 13 + 11) % 1000000
digest = hashlib.sha256(("spume:%d" % nonce).encode("utf-8")).hexdigest()
print("pierpass-" + digest[12:20])
PY
}

# ---- 1. visible deliverables: dock 21 ----
EXPECTED_21="$(expect_for 21)"

if ! python3 /app/claim_pass.py 21 >/tmp/spume_visible.out 2>/tmp/spume_visible.err; then
  fail "claim_pass.py 21 exited non-zero"
else
  got="$(tail -n 1 /tmp/spume_visible.out | tr -d '[:space:]')"
  [ "$got" = "$EXPECTED_21" ] || fail "claim_pass.py 21 printed '$got', expected '$EXPECTED_21'"
fi

if [ -f /app/final_message.txt ]; then
  msg="$(tr -d '[:space:]' < /app/final_message.txt)"
  [ "$msg" = "$EXPECTED_21" ] || fail "final_message.txt is '$msg', expected '$EXPECTED_21'"
else
  fail "missing /app/final_message.txt"
fi

if [ -f /app/claim_receipt.json ]; then
  if ! python3 - "$EXPECTED_21" <<'PY'
import json, sys
expected = sys.argv[1]
j = json.loads(open("/app/claim_receipt.json", encoding="utf-8").read())
if not isinstance(j, dict):
    raise SystemExit("receipt is not an object")
if j.get("status") != "claimed":
    raise SystemExit("receipt status != claimed")
if j.get("dock") != 21:
    raise SystemExit("receipt dock != 21")
if j.get("final") != expected:
    raise SystemExit("receipt final != expected")
PY
  then
    fail "claim_receipt.json does not match the dock-21 claim"
  fi
else
  fail "missing /app/claim_receipt.json"
fi

# ---- 2. hidden cases: re-run the deliverable live ----
if ! python3 - <<'PY'
import hashlib, json, os, subprocess, sys

failures = []


def expect_final(dock):
    nonce = (dock * 13 + 11) % 1000000
    digest = hashlib.sha256(("spume:%d" % nonce).encode("utf-8")).hexdigest()
    return "pierpass-" + digest[12:20]


def run_claim(arg):
    r = subprocess.run([sys.executable, "/app/claim_pass.py", arg],
                       capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout, r.stderr


hidden = "/tests/hidden"
cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
if not cases:
    failures.append("no hidden cases present")
for c in cases:
    base = os.path.join(hidden, c)
    try:
        spec = json.load(open(os.path.join(base, "case.json")))
    except Exception as e:
        failures.append("hidden '%s': unreadable case.json (%s)" % (c, e))
        continue
    arg = str(spec["arg"])
    kind = spec["expect"]  # "open" or "closed"
    code, out, err = run_claim(arg)
    if kind == "open":
        dock = int(arg)
        want = expect_final(dock)
        # cross-check against the shipped expected.txt when present
        exp_path = os.path.join(base, "expected.txt")
        if os.path.isfile(exp_path):
            shipped = open(exp_path).read().strip()
            if shipped != want:
                failures.append("hidden '%s': shipped expected.txt disagrees with formula" % c)
        if code != 0:
            failures.append("hidden '%s': exit %d (wanted 0); stderr=%s"
                            % (c, code, err[-120:]))
        if want not in out:
            failures.append("hidden '%s': expected %r in stdout, got %r"
                            % (c, want, out[-120:]))
    else:
        if code == 0:
            failures.append("hidden '%s': expected non-zero exit, got 0" % c)
        if "pierpass-" in out:
            failures.append("hidden '%s': leaked a pierpass string on stdout" % c)
        if not err.strip():
            failures.append("hidden '%s': no diagnostic on stderr" % c)

sys.exit(1 if failures else 0)
PY
then
  fail "hidden case checks failed"
fi

if [ "$PASS" = "1" ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
