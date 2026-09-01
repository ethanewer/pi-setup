#!/bin/bash
# Verifier for brass-dunlin: enforces the no-modify rule on /app/telemetry,
# checks the authored /app/rules.json, RECOMPUTES the visible case
# independently and compares /app/alert.json + /app/report.json, and EXECUTES
# the deliverable program (/app/monitor.py) on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied telemetry logs (instruction: do not modify).
PRISTINE_EDGE1_SHA="8844b1f89a7e7ae421b6b9cf9569148f9f2565146311ca5e59b1d321dd7244e5"
PRISTINE_EDGE2_SHA="fc97e39dba0abadf7f197f1a937c231b8ec372f8745b08f126512c885a6a3b05"

no_modify_broken=0
for f in /app/telemetry/edge-1.log /app/telemetry/edge-2.log; do
    if [ ! -f "$f" ]; then
        echo "no-modify: $f missing" >&2
        no_modify_broken=1
    fi
done
if [ "$no_modify_broken" -eq 0 ]; then
    s1="$(sha256sum /app/telemetry/edge-1.log | awk '{print $1}')"
    s2="$(sha256sum /app/telemetry/edge-2.log | awk '{print $1}')"
    if [ "$s1" != "$PRISTINE_EDGE1_SHA" ] || [ "$s2" != "$PRISTINE_EDGE2_SHA" ]; then
        echo "no-modify: telemetry logs were modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

sys.path.insert(0, "/tests")
import recompute

SOLVE = "/app/monitor.py"
RULES = "/app/rules.json"
ALERT = "/app/alert.json"
REPORT = "/app/report.json"
TELEMETRY = ["/app/telemetry/edge-1.log", "/app/telemetry/edge-2.log"]

PLACEHOLDER_TS = "2026-01-01T00:00:00Z"

failures = []
if int(sys.argv[1]):
    failures.append("telemetry logs modified or missing (no-modify rule)")

# ---- guard: pristine telemetry digests (defense in depth) ----
PRISTINE = {
    "/app/telemetry/edge-1.log": None,
    "/app/telemetry/edge-2.log": None,
}

def load_json(path):
    with open(path) as fh:
        return json.load(fh)

def run_monitor(args, timeout=120):
    out_files = (ALERT, REPORT)
    for p in out_files:
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run([sys.executable, SOLVE] + args,
                           capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        return None, "monitor.py crashed: %s" % e
    if r.returncode != 0:
        return None, "monitor.py exited %d" % r.returncode
    return out_files, None

def check_outputs():
    """Both outputs exist, parse, and satisfy the schemas."""
    try:
        a = load_json(ALERT)
        ra = recompute.canon_alert(a)
    except Exception as e:
        return None, None, "alert.json invalid: %s" % e
    try:
        rp = load_json(REPORT)
        rr = recompute.canon_report(rp)
    except Exception as e:
        return None, None, "report.json invalid: %s" % e
    return ra, rr, None

# ---- 1. deliverable program present ----
if not os.path.isfile(SOLVE):
    failures.append("missing /app/monitor.py")

# ---- 2. authored rules.json contains the five required rules ----
required = {
    "cpu_sizzle": ("cpu_temp", 85.0, 3, "critical"),
    "mem_pressure": ("mem_pct", 92.0, 2, "high"),
    "disk_hothead": ("disk_temp", 68.0, 1, "medium"),
    "link_flap": ("link_errors", 50.0, 5, "high"),
    "fan_wail": ("fan_noise", 62.0, 9, "low"),
}
if not os.path.isfile(RULES):
    failures.append("missing /app/rules.json")
else:
    try:
        data = load_json(RULES)
        assert isinstance(data, dict) and isinstance(data.get("rules"), list)
        found = {}
        for r in data["rules"]:
            if isinstance(r, dict) and isinstance(r.get("id"), str):
                found[r["id"]] = r
        for rid, (metric, mx, thr, sev) in required.items():
            r = found.get(rid)
            if r is None:
                failures.append("rules.json missing rule '%s'" % rid)
                continue
            if r.get("metric") != metric:
                failures.append("rule '%s': metric must be %s" % (rid, metric))
            try:
                if float(r.get("max")) != mx:
                    failures.append("rule '%s': max must be %s" % (rid, mx))
            except Exception:
                failures.append("rule '%s': max must be numeric %s" % (rid, mx))
            if r.get("threshold") != thr or isinstance(r.get("threshold"), bool):
                failures.append("rule '%s': threshold must be %d" % (rid, thr))
            if r.get("severity") != sev:
                failures.append("rule '%s': severity must be %s" % (rid, sev))
    except Exception as e:
        failures.append("rules.json not a valid rules object: %s" % e)

# ---- 3. visible case: run with defaults, compare with independent recompute ----
if os.path.isfile(SOLVE) and os.path.isfile(RULES):
    _, err = run_monitor([])
    if err:
        failures.append("visible run failed: %s" % err)
    else:
        got_a, got_r, err = check_outputs()
        if err:
            failures.append("visible outputs: %s" % err)
        else:
            try:
                wa, we, ws = recompute.recompute(RULES, TELEMETRY)
                # recompute returns tuples; wrap into canonical shape
                want_a = wa
                want_r = (
                    [(e["rule"], e["device"], round(float(e["value"]), 6), e["line"])
                     for e in we],
                    ws,
                )
                if got_a != want_a:
                    failures.append("visible alert.json != recomputed alerts")
                if got_r != want_r:
                    failures.append("visible report.json != recomputed report")
            except Exception as e:
                failures.append("visible recompute failed: %s" % e)

# ---- 4. hidden cases: execute monitor.py on hidden rules + logs ----
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if len(cases) < 2:
        failures.append("fewer than 2 hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        rules_p = os.path.join(base, "rules.json")
        logs_txt = os.path.join(base, "logs.txt")
        exp_a = os.path.join(base, "expected_alert.json")
        exp_r = os.path.join(base, "expected_report.json")
        if not all(os.path.isfile(p) for p in (rules_p, logs_txt, exp_a, exp_r)):
            failures.append("hidden '%s' malformed" % c)
            continue
        try:
            log_names = [l.strip() for l in open(logs_txt) if l.strip()]
            log_args = [os.path.join(base, n) for n in log_names]
        except Exception:
            failures.append("hidden '%s': unreadable logs.txt" % c)
            continue
        _, err = run_monitor([rules_p] + log_args)
        if err:
            failures.append("hidden '%s' run failed: %s" % (c, err))
            continue
        got_a, got_r, err = check_outputs()
        if err:
            failures.append("hidden '%s': %s" % (c, err))
            continue
        try:
            want_a_raw = load_json(exp_a)
            want_r_raw = load_json(exp_r)
            # expected artifacts carry a placeholder timestamp
            want_a_raw["timestamp"] = PLACEHOLDER_TS
            want_r_raw["timestamp"] = PLACEHOLDER_TS
            if got_a != recompute.canon_alert(want_a_raw):
                failures.append("hidden '%s': alert mismatch" % c)
            if got_r != recompute.canon_report(want_r_raw):
                failures.append("hidden '%s': report mismatch" % c)
        except Exception as e:
            failures.append("hidden '%s': expected unreadable: %s" % (c, e))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
