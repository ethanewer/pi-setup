#!/bin/bash
# fume-latch verifier: checks the visible receipt deliverable, then re-runs
# the agent's client (/app/apply_fixes.py) against fresh hidden desk sessions
# under strict fix budgets. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -uo pipefail
PY="$(command -v python3)"
reward=1
mkdir -p /logs/verifier
PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null || true; done;
  echo "${reward:-0}" > /logs/verifier/reward.txt; }
trap cleanup EXIT

if [ ! -f /app/apply_fixes.py ]; then echo "VERIFIER: missing /app/apply_fixes.py" >&2; reward=0; fi
if [ ! -f /app/receipt.json ]; then echo "VERIFIER: missing /app/receipt.json" >&2; reward=0; fi

if "$PY" - <<'PY'
import hashlib, json, os, subprocess, sys, urllib.request

fail = []
CLIENT = "/app/apply_fixes.py"


def expected_bytes(expected_lines):
    return ("\n".join(expected_lines) + "\n").encode("utf-8")


def get_json(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def run_case(label, case_dir, port, order_path, plate_path):
    """Start a fresh desk session for `case_dir` and re-run the client."""
    order = json.load(open(order_path))
    expected = json.load(open(os.path.join(case_dir, "expected.json")))
    case = {"session": "verify-" + label,
            "workfile": plate_path,
            "budget": len(order.get("fixes", [])),
            "expected": expected}
    case_path = "/tmp/fume_%s_case.json" % label
    with open(case_path, "w") as f:
        json.dump(case, f)
    proc = subprocess.Popen(
        [sys.executable, "/app/desk_service.py", "--serve",
         "--port", str(port), "--case", case_path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    import time
    time.sleep(1.0)
    receipt_path = "/tmp/fume_%s_receipt.json" % label
    try:
        r = subprocess.run(
            [sys.executable, CLIENT, "--url", "http://127.0.0.1:%d" % port,
             "--order", order_path, "--receipt", receipt_path],
            capture_output=True, text=True, timeout=120)
    finally:
        proc.terminate()
        proc.wait()
    if r.returncode != 0:
        fail.append("%s: client exit %d (%s)" % (label, r.returncode,
                                                 (r.stderr or r.stdout).strip()[-300:]))
    if not os.path.exists(receipt_path):
        fail.append("%s: no receipt written" % label)
        return
    try:
        receipt = json.load(open(receipt_path))
    except Exception as e:
        fail.append("%s: receipt unreadable (%s)" % (label, e))
        return
    exp_sha = hashlib.sha256(expected_bytes(expected)).hexdigest()
    if receipt.get("all_fixed") is not True:
        fail.append("%s: receipt.all_fixed=%r" % (label, receipt.get("all_fixed")))
    if receipt.get("status") != "open":
        fail.append("%s: receipt.status=%r (budget-exceeded = too many fix attempts)"
                    % (label, receipt.get("status")))
    if not isinstance(receipt.get("fixes_used"), int) \
            or receipt["fixes_used"] > len(order.get("fixes", [])):
        fail.append("%s: fixes_used=%r exceeds the work-order budget"
                    % (label, receipt.get("fixes_used")))
    if receipt.get("sha256") != exp_sha:
        fail.append("%s: receipt.sha256 mismatch" % label)
    # Session must not have flipped to budget-exceeded either.
    # (The service was terminated above; the workfile check is authoritative.)
    got = open(plate_path, "rb").read()
    if got != expected_bytes(expected):
        fail.append("%s: plate file does not match expected content" % label)


# ---- visible deliverable: /app/receipt.json against /app/desk/visible_case.json
try:
    vcase = json.load(open("/app/desk/visible_case.json"))
    vorder = json.load(open("/app/work_order.json"))
    vrec = json.load(open("/app/receipt.json"))
    vexp = vcase["expected"]
    vsha = hashlib.sha256(expected_bytes(vexp)).hexdigest()
    if vrec.get("all_fixed") is not True or vrec.get("status") != "open":
        fail.append("visible: receipt not clean (all_fixed=%r status=%r)"
                    % (vrec.get("all_fixed"), vrec.get("status")))
    if not isinstance(vrec.get("fixes_used"), int) \
            or vrec["fixes_used"] > vcase["budget"]:
        fail.append("visible: fixes_used=%r exceeds budget %r"
                    % (vrec.get("fixes_used"), vcase.get("budget")))
    if vrec.get("sha256") != vsha:
        fail.append("visible: receipt.sha256 mismatch")
    if open("/app/plate.txt", "rb").read() != expected_bytes(vexp):
        fail.append("visible: /app/plate.txt does not match expected content")
except Exception as e:
    fail.append("visible: %s" % e)

# ---- hidden sessions (fresh services, strict budgets)
if os.path.isdir("/tests/hidden"):
    port = 8491
    for case in sorted(os.listdir("/tests/hidden")):
        cdir = os.path.join("/tests/hidden", case)
        if not os.path.isdir(cdir):
            continue
        plate = "/tmp/fume_%s_plate.txt" % case
        with open(os.path.join(cdir, "plate.txt"), "rb") as src, \
                open(plate, "wb") as dst:
            dst.write(src.read())
        run_case(case, cdir, port, os.path.join(cdir, "work_order.json"), plate)
        port += 1

if fail:
    print("FAILURES:", *fail, sep="\n  ")
    sys.exit(2)
print("fume-latch: all sessions clean within budget")
PY
then
  :
else
  reward=0
fi

echo "fume-latch reward=$reward"
