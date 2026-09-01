#!/usr/bin/env bash
# moss-forge verifier (executes-deliverable).
# Rebuilds the release binary from the agent's fixed source, then EXECUTES it
# on the visible workload and every hidden workload, comparing against an
# independent reference simulation of the driver. Protected files are
# hash-checked. Writes 1.0/0.0 to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- 0. deliverables present -------------------------------------------- #
[ -f /app/forge.c ]    || fail "missing /app/forge.c"
[ -f /app/forgebench ] || fail "missing /app/forgebench"
[ -f /app/main.c ]     || fail "missing /app/main.c"
[ -f /app/Makefile ]   || fail "missing /app/Makefile"
[ -f /app/workload.txt ] || fail "missing /app/workload.txt"
if [ "$reward" -eq 0 ]; then echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; fi

# ---- 1. protected files must remain byte-identical ----------------------- #
MAIN_SHA=$(sha256sum /app/main.c | cut -d' ' -f1)
MK_SHA=$(sha256sum /app/Makefile | cut -d' ' -f1)
[ "$MAIN_SHA" = "e7ade43415b67b04b7c237bd1fef3553f5380561f44d5068e9db27756486d4e7" ] \
  || fail "main.c was modified (protected)"
[ "$MK_SHA" = "ece4de7716d611008c6dfaac1511cc21830a2bf4ef89e5cdd5dbaaf82a62bad1" ] \
  || fail "Makefile was modified (protected)"
if [ "$reward" -eq 0 ]; then echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; fi

# ---- 2. rebuild from the agent's fixed source ---------------------------- #
if ! (cd /app && make clean >/dev/null 2>&1 && make) >/tmp/forge_build.log 2>&1; then
  fail "rebuild failed: $(tail -5 /tmp/forge_build.log)"
  echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0
fi
[ -x /app/forgebench ] || fail "make did not produce /app/forgebench"
if [ "$reward" -eq 0 ]; then echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; fi

# ---- 3. run every workload against the reference simulation -------------- #
python3 - <<'PY'
import os, subprocess, sys

BENCH = "/app/forgebench"
M = 2**64

failures = []

def sim(path):
    """Independent reference simulation of the documented driver semantics."""
    live = {}
    for raw in open(path):
        t = raw.split()
        if not t:
            continue
        op = t[0]
        if op == "A" and len(t) >= 3:
            try:
                n = int(t[2])
            except ValueError:
                continue
            if n < 0:
                continue
            live.pop(t[1], None)
            live[t[1]] = [n, 0]
        elif op == "W" and len(t) >= 3:
            try:
                v = int(t[2])
            except ValueError:
                continue
            if v < 0 or t[1] not in live:
                continue
            live[t[1]][1] = v & 0xFF
        elif op == "F" and len(t) >= 2:
            live.pop(t[1], None)
    return sum(s * (f + 1) for s, f in live.values()) % M


def run_case(workload, tag):
    try:
        r = subprocess.run([BENCH, workload], capture_output=True,
                           text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return "timed out"
    if r.returncode != 0:
        return "exit %d (expected clean run)" % r.returncode
    want = "FORGE-OK %d" % sim(workload)
    got = r.stdout.strip()
    if got != want:
        return "output %r != expected %r" % (got[:80], want)
    return None


err = run_case("/app/workload.txt", "visible")
if err:
    failures.append("visible workload: %s" % err)

hidden = "/tests/hidden"
if not os.path.isdir(hidden):
    failures.append("no hidden cases present")
else:
    cases = sorted(os.listdir(hidden))
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        wl = os.path.join(hidden, case, "workload.txt")
        if not os.path.isfile(wl):
            failures.append("hidden '%s' malformed" % case)
            continue
        err = run_case(wl, case)
        if err:
            failures.append("hidden '%s': %s" % (case, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -ne 0 ]; then reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "final-reward=$reward"
exit 0
