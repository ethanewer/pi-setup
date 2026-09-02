#!/bin/bash
# Verifier for juniper-hollow: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app fixtures, and
# EXECUTES the deliverable program (/app/triage.py) on the visible case and on
# every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_RULES_SHA="0e1d23cbd98605d02e2f8402bd6d75b77777e3eaba76f9e2b9702eb137dd59ba"
PRISTINE_GW_SHA="e40e02559d4b180338aebb48c3d0c0995476469b3622bab0cf76eb91220a0483"
PRISTINE_DNS_SHA="6a3d35accfccf40d381ca4e8613ac6e11ec64d4a8d0b26207c2b8cf7d9f18050"

no_modify_broken=0
check_pristine() {
    local path="$1" want="$2" label="$3"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
        return
    fi
    local actual
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $label was modified" >&2
        no_modify_broken=1
    fi
}
check_pristine /app/rules.json "$PRISTINE_RULES_SHA" "/app/rules.json"
check_pristine /app/edge/gateway.log "$PRISTINE_GW_SHA" "/app/edge/gateway.log"
check_pristine /app/edge/dns.log "$PRISTINE_DNS_SHA" "/app/edge/dns.log"

python3 - "$no_modify_broken" <<'PY'
import json, os, re, subprocess, sys, tempfile

SOLVE = "/app/triage.py"
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
no_modify_broken = int(sys.argv[1])


def check_ts(ts):
    return isinstance(ts, str) and TS_RE.match(ts) is not None


def cmp_alert(got, want):
    """alert.json: timestamp only validated, rest compared exactly."""
    if not isinstance(got, dict) or set(got.keys()) != {"timestamp", "alerts"}:
        return False
    if not check_ts(got.get("timestamp")):
        return False
    return got["alerts"] == want["alerts"]


def cmp_report(got, want):
    """report.json: timestamp only validated, rest compared exactly."""
    if not isinstance(got, dict):
        return False
    if set(got.keys()) != {"timestamp", "events", "statistics"}:
        return False
    if not check_ts(got.get("timestamp")):
        return False
    if got["events"] != want["events"]:
        return False
    return got["statistics"] == want["statistics"]


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def run_case(rules, logs, exp_alert_path, exp_report_path, outdir):
    r = subprocess.run(
        [sys.executable, SOLVE, rules, outdir] + logs,
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        return False
    got_alert = load_json(os.path.join(outdir, "alert.json"))
    got_report = load_json(os.path.join(outdir, "report.json"))
    want_alert = load_json(exp_alert_path)
    want_report = load_json(exp_report_path)
    if got_alert is None or got_report is None:
        return False
    if want_alert is None or want_report is None:
        return False
    return cmp_alert(got_alert, want_alert) and cmp_report(got_report, want_report)


failures = []
if no_modify_broken:
    failures.append("visible fixtures modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/triage.py")
else:
    # --- visible case: EXECUTE triage.py on the live supplied fixtures ---
    if not (os.path.isfile("/app/rules.json")
            and os.path.isfile("/app/edge/gateway.log")
            and os.path.isfile("/app/edge/dns.log")):
        failures.append("visible fixtures missing")
    else:
        with tempfile.TemporaryDirectory() as td:
            if not run_case("/app/rules.json",
                            ["/app/edge/gateway.log", "/app/edge/dns.log"],
                            "/tests/expected/alert.json",
                            "/tests/expected/report.json", td):
                failures.append("visible case failed")

    # --- visible-case deliverables: /app/alert.json and /app/report.json ---
    got_alert = load_json("/app/alert.json")
    want_alert = load_json("/tests/expected/alert.json")
    if got_alert is None or want_alert is None:
        failures.append("alert.json missing or unreadable")
    elif not cmp_alert(got_alert, want_alert):
        failures.append("/app/alert.json does not match visible expected")

    got_report = load_json("/app/report.json")
    want_report = load_json("/tests/expected/report.json")
    if got_report is None or want_report is None:
        failures.append("report.json missing or unreadable")
    elif not cmp_report(got_report, want_report):
        failures.append("/app/report.json does not match visible expected")

    # --- hidden cases: genuinely distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            rules = os.path.join(base, "rules.json")
            exp_a = os.path.join(base, "alert.json")
            exp_r = os.path.join(base, "report.json")
            logs = sorted(
                os.path.join(base, n) for n in os.listdir(base)
                if n.endswith(".log")
            )
            if not (os.path.isfile(rules) and os.path.isfile(exp_a)
                    and os.path.isfile(exp_r) and logs):
                failures.append("hidden '%s' malformed" % c)
                continue
            with tempfile.TemporaryDirectory() as td:
                if not run_case(rules, logs, exp_a, exp_r, td):
                    failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
