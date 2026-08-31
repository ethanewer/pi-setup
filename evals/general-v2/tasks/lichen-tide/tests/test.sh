#!/bin/bash
# Verifier for lichen-tide: checks the visible deliverables, ENFORCES the
# no-modify rule on the supplied /app fixtures, and EXECUTES /app/triage.py on
# the visible case and on every hidden case in /tests/hidden. Writes REWARD
# (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_RULES_SHA="8ec6e2c86ab205a53812a4463b43a779b85bc00aac7a06dd921347caa310b77e"
PRISTINE_GATEWAY_SHA="8f49dc980db14e1ded4ea4e3808d510a23c262ad3ae9238b0d174cbb5b9da987"
PRISTINE_AUDIT_SHA="59be293836b45daee691b71196944a536dac865f375ae709a5ee199043fa1742"

no_modify_broken=0
check_sha() {
    local path="$1" want="$2"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
        return
    fi
    local actual
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $path was modified" >&2
        no_modify_broken=1
    fi
}
check_sha /app/rules.json "$PRISTINE_RULES_SHA"
check_sha /app/logs/gateway.log "$PRISTINE_GATEWAY_SHA"
check_sha /app/logs/audit.log "$PRISTINE_AUDIT_SHA"

python3 - "$no_modify_broken" <<'PY'
import glob, json, os, subprocess, sys

SOLVE = "/app/triage.py"
no_modify_broken = int(sys.argv[1])


def check_timestamp(ts):
    assert isinstance(ts, str) and ts.strip(), "timestamp must be a nonempty string"


def check_alerts(alerts, want):
    assert isinstance(alerts, list)
    for a in alerts:
        assert isinstance(a, dict)
        assert set(a.keys()) == {"id", "severity", "matches", "ips"}, sorted(a.keys())
        assert isinstance(a["id"], str) and isinstance(a["severity"], str)
        assert isinstance(a["matches"], int)
        assert isinstance(a["ips"], list) and all(isinstance(x, str) for x in a["ips"])
    assert alerts == want, (alerts, want)


def check_report(report, want):
    assert isinstance(report, dict)
    assert set(report.keys()) == {"timestamp", "events", "statistics"}, sorted(report.keys())
    check_timestamp(report["timestamp"])
    events = report["events"]
    assert isinstance(events, list)
    for e in events:
        assert isinstance(e, dict)
        assert set(e.keys()) == {"rule", "client", "line"}, sorted(e.keys())
        assert isinstance(e["rule"], str) and isinstance(e["line"], str)
        assert e["client"] is None or isinstance(e["client"], str)
    assert events == want["events"], "events mismatch"
    stats = report["statistics"]
    assert isinstance(stats, dict)
    assert set(stats.keys()) == set(want["statistics"].keys()), "statistics keys mismatch"
    for rid, ws in want["statistics"].items():
        s = stats[rid]
        assert isinstance(s, dict)
        assert set(s.keys()) == {"id", "keyword", "min_level", "threshold",
                                 "severity", "matches", "unique_ips", "ips"}, sorted(s.keys())
        assert s["id"] == rid
        assert s["matches"] == ws["matches"], (rid, s["matches"], ws["matches"])
        assert s["ips"] == ws["ips"], (rid, s["ips"], ws["ips"])
        assert s["unique_ips"] == len(s["ips"])


def run_case(rules, logs, expected_path):
    alert_out = "/tmp/lichen_tide_alert_out.json"
    report_out = "/tmp/lichen_tide_report_out.json"
    for p in (alert_out, report_out):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run(
        [sys.executable, SOLVE, rules, alert_out, report_out] + list(logs),
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0 or not (os.path.exists(alert_out) and os.path.exists(report_out)):
        return False
    try:
        with open(alert_out) as f:
            got_alert = json.load(f)
        with open(report_out) as f:
            got_report = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        assert isinstance(got_alert, dict)
        assert set(got_alert.keys()) == {"timestamp", "alerts"}, sorted(got_alert.keys())
        check_timestamp(got_alert["timestamp"])
        check_alerts(got_alert["alerts"], want["alerts"])
        check_report(got_report, want)
        return True
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible fixtures modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/triage.py")
else:
    # --- visible case: EXECUTE triage.py on the live supplied fixtures ---
    visible_logs = ["/app/logs/gateway.log", "/app/logs/audit.log"]
    if not (os.path.isfile("/app/rules.json") and all(os.path.isfile(p) for p in visible_logs)):
        failures.append("visible fixtures missing")
    elif not run_case("/app/rules.json", visible_logs, "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverables must exist and match the visible expected ---
    if os.path.isfile("/app/alert.json") and os.path.isfile("/app/report.json"):
        try:
            with open("/app/alert.json") as f:
                got_alert = json.load(f)
            with open("/app/report.json") as f:
                got_report = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            assert isinstance(got_alert, dict)
            assert set(got_alert.keys()) == {"timestamp", "alerts"}, sorted(got_alert.keys())
            check_timestamp(got_alert["timestamp"])
            check_alerts(got_alert["alerts"], want["alerts"])
            check_report(got_report, want)
        except Exception:
            failures.append("alert.json / report.json do not match visible expected")
    else:
        failures.append("missing /app/alert.json or /app/report.json")

    # --- hidden cases: genuinely distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            rules = os.path.join(base, "rules.json")
            exp = os.path.join(base, "expected.json")
            logs = sorted(glob.glob(os.path.join(base, "log*.txt")))
            if not (os.path.isfile(rules) and os.path.isfile(exp) and logs):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(rules, logs, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
