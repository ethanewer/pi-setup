#!/bin/bash
# Verifier for fume-anchor: recomputes the expected payload with its own
# reference derivation, then EXECUTES the deliverable /app/issue_token.py on
# the visible state directory and on every hidden state directory, and checks
# the /app/answer.txt deliverable. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier

python3 - <<'PY'
import os, subprocess, sys

SOLVER = "/app/issue_token.py"
ANSWER = "/app/answer.txt"
failures = []


# ---- reference derivation (independent of the deliverable) ----
def ref_base(sd):
    b = None
    for line in open(os.path.join(sd, "deploy.env")):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        key, _, val = s.partition("=")
        if key.strip() == "SERIES_BASE":
            b = int(val.strip())
    assert b is not None
    return b


def ref_mul(sd):
    m = None
    for line in open(os.path.join(sd, "rotation.txt")):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        t = s.split()
        if len(t) >= 4 and t[0] == "slot" and t[2] == "=" and t[1] == "anchor":
            m = int(t[3])
    assert m is not None
    return m


def ref_prime(sd):
    for line in open(os.path.join(sd, "docs", "epoch.md")):
        if "epoch-prime" in line:
            return int(line.rsplit(":", 1)[1].strip())
    raise AssertionError("epoch-prime missing")


def ref_offset(sd):
    n = 0
    for line in open(os.path.join(sd, "nodes.list")):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.split()[0] == "active":
            n += 1
    return n


def expected(sd):
    return (ref_base(sd) * ref_mul(sd) + ref_offset(sd)) % ref_prime(sd)


def run_solver(sd):
    try:
        r = subprocess.run([sys.executable, SOLVER, sd],
                           capture_output=True, text=True, timeout=60)
    except Exception as e:
        failures.append("solver crashed on %s: %s" % (sd, e))
        return None
    if r.returncode != 0:
        failures.append("solver exited %d on %s (%s)"
                        % (r.returncode, sd, r.stderr.strip()[:200]))
        return None
    out = r.stdout.strip()
    try:
        return int(out)
    except ValueError:
        failures.append("solver stdout not a single integer on %s: %r"
                        % (sd, r.stdout[:100]))
        return None


if not os.path.isfile(SOLVER):
    failures.append("missing /app/issue_token.py")
else:
    # --- visible case: run the deliverable on /app/state ---
    got = run_solver("/app/state")
    want = expected("/app/state")
    if got is not None and got != want:
        failures.append("visible case: got %r want %r" % (got, want))

    # --- visible-case deliverable: /app/answer.txt ---
    if not os.path.isfile(ANSWER):
        failures.append("missing /app/answer.txt")
    else:
        try:
            val = int(open(ANSWER).read().strip())
            if val != want:
                failures.append("answer.txt %r != expected %r" % (val, want))
        except Exception as e:
            failures.append("answer.txt unreadable: %s" % e)

    # --- hidden cases: distinct state directories ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            sd = os.path.join(hidden_dir, c)
            if not (os.path.isfile(os.path.join(sd, "deploy.env"))
                    and os.path.isfile(os.path.join(sd, "rotation.txt"))
                    and os.path.isfile(os.path.join(sd, "docs", "epoch.md"))
                    and os.path.isfile(os.path.join(sd, "nodes.list"))):
                failures.append("hidden '%s' malformed" % c)
                continue
            got = run_solver(sd)
            want = expected(sd)
            if got is not None and got != want:
                failures.append("hidden '%s': got %r want %r" % (c, got, want))
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
reward=0
if [ "$rc" -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
