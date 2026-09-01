#!/bin/bash
# Verifier for sable-wicket: audits the patchdeck attempt log against the
# audit report (budget of one attempt per finding, all five APPLIED exactly
# once, cryptographic ties to the delivered file), then re-tests every
# function of the delivered /app/lib/wickkit.py on the visible case and on
# hidden vectors under /tests/hidden. Writes REWARD to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib, json, os, sys

LOG = "/app/tools/patchdeck.log"
LIB = "/app/lib/wickkit.py"
BUDGET = 5
EXPECTED_IDS = {"F-01", "F-02", "F-03", "F-04", "F-05"}
# sha256 of each audited defective line (computed from the pristine module at
# authoring time; the runtime audit report is never trusted for this).
AUDIT_SHA = {
    "F-01": ("a993f89e7983b0667b9e45d8615216b44f3a3b785dfa45105e0228397b429cef", 11),
    "F-02": ("4ad9ae2ac32dba8169d1ec5b544f1a648813d5e2b06b8218883d85a70b99170c", 18),
    "F-03": ("ab0137fb73021081179df8227fc3871e9e5805740c2cf6beba859b1f539233e9", 26),
    "F-04": ("b029e1314f33e979252b7202e9a04f5261ed61d9a1983dc43d55380cf2dc1de1", 32),
    "F-05": ("b34e287a5c4d16559b5ccb2c5539117d0594ce6694efd0c19e87a3eddf8d7040", 37),
}
failures = []


def sha(t):
    return hashlib.sha256(t.encode("utf-8")).hexdigest()


def run_calls(calls):
    sys.path.insert(0, "/app/lib")
    for mod in [m for m in list(sys.modules) if m.startswith("wickkit")]:
        del sys.modules[mod]
    import wickkit
    out = []
    for call in calls:
        fn, args = call[0], call[1:]
        if not hasattr(wickkit, fn) or not callable(getattr(wickkit, fn)):
            raise ValueError("unknown function %r" % fn)
        out.append(getattr(wickkit, fn)(*args))
    return out


for d in (LOG, LIB):
    if not os.path.isfile(d):
        failures.append("missing deliverable %s" % d)

# --- 1. Audit the attempt log ---
entries = []
if os.path.isfile(LOG):
    try:
        with open(LOG) as fh:
            for ln, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                entries.append(json.loads(line))  # guarded: any bad line fails below
    except Exception as e:
        failures.append("patchdeck.log not parseable JSON-lines: %r" % (e,))

if not failures:
    if len(entries) != BUDGET:
        failures.append("attempt budget blown: %d attempts logged (budget %d)"
                        % (len(entries), BUDGET))
    applied = {}
    for e in entries:
        if e.get("result") != "APPLIED":
            failures.append("attempt %s: %s" % (e.get("attempt"), e.get("result")))
            continue
        fid = e.get("finding")
        if fid not in EXPECTED_IDS or fid in applied:
            failures.append("attempt %s: unexpected or duplicate finding %r"
                            % (e.get("attempt"), fid))
            continue
        applied[fid] = e
        exp_sha, exp_line = AUDIT_SHA[fid]
        if e.get("sha_old") != exp_sha or e.get("line") != exp_line:
            failures.append("%s: logged request does not match the audited line" % fid)
    missing = EXPECTED_IDS - set(applied)
    if missing:
        failures.append("findings never applied: %s" % sorted(missing))

    # --- 2. Tie each logged request to the delivered file's current lines ---
    if os.path.isfile(LIB):
        lines = open(LIB, encoding="utf-8").read().split("\n")
        for fid, e in applied.items():
            ln = e.get("line")
            if not isinstance(ln, int) or not (1 <= ln <= len(lines)):
                failures.append("%s: bad line number in log" % fid)
                continue
            if sha(lines[ln - 1]) != e.get("sha_new"):
                failures.append("%s: delivered line %d does not match the applied request"
                                % (fid, ln))

# --- 3. Behavior: visible case + hidden vectors on the delivered module ---
def check_case(calls_path, outs_path, tag):
    try:
        calls = json.load(open(calls_path))["calls"]
        want = json.load(open(outs_path))["outs"]
        got = run_calls(calls)
    except Exception as e:
        failures.append("%s: crashed or invalid: %r" % (tag, e))
        return
    if got != want:
        failures.append("%s: wrong results" % tag)


if os.path.isfile(LIB):
    if os.path.isfile("/tests/expected.json"):
        exp = json.load(open("/tests/expected.json"))
        check_calls = exp["calls"]
        # visible case is served as calls+outs in one file
        try:
            got = run_calls(check_calls)
            if got != exp["outs"]:
                failures.append("visible case: wrong results")
        except Exception as e:
            failures.append("visible case: crashed: %r" % (e,))
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(d for d in os.listdir(hidden)
                       if os.path.isfile(os.path.join(hidden, d, "in.json")))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden, c)
            check_case(os.path.join(base, "in.json"), os.path.join(base, "out.json"),
                       "hidden/%s" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "sable-wicket reward=$reward"
