#!/bin/bash
# Verifier for topaz-vane: ENFORCES the no-modify rule on /app/logs, validates
# the deliverable schemas, and EXECUTES the deliverable program (/app/triage.py)
# on the visible inputs and on every hidden case in /tests/hidden, comparing
# against an independently recomputed reference. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible logs (the instruction tells the agent
# not to modify them; tampering defeats the visible-case check).
PRISTINE_GATEWAY_SHA="ebc71e1315e6fd329172574133ab0b67847ee42ac6fd8ed8b3e2284cf109abe9"
PRISTINE_DNS_SHA="1b2ba426c96fd6deca86b262d3008e254a4342a06ab3ed3a05b26e786ca8bf1f"

no_modify_broken=0
for pair in "/app/logs/gateway.log:$PRISTINE_GATEWAY_SHA" "/app/logs/dns.log:$PRISTINE_DNS_SHA"; do
    f="${pair%%:*}"
    want="${pair#*:}"
    if [ ! -f "$f" ]; then
        echo "no-modify: $f missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$f" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $f was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json, os, re, subprocess, sys

PROG = "/app/triage.py"
ALERT_OUT = "/app/alert.json"
REPORT_OUT = "/app/report.json"
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
no_modify_broken = int(sys.argv[1])


# ---------- independent reference implementation ----------
def ref_load_rules(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return []
    if not isinstance(data, dict):
        return []
    rules = data.get("rules")
    if not isinstance(rules, list):
        return []
    out = []
    for entry in rules:
        if not isinstance(entry, dict):
            continue
        kw = entry.get("keyword")
        if not isinstance(kw, str):
            kw = None
        thr = entry.get("threshold", 0)
        if isinstance(thr, bool) or not isinstance(thr, int):
            thr = 0
        sev = entry.get("severity", "info")
        if not isinstance(sev, str):
            sev = "info"
        out.append({"id": entry.get("id"), "keyword": kw,
                    "threshold": thr, "severity": sev})
    return out


def ref_scan(rules, logs):
    events = []
    stats = {}
    for rule in rules:
        stats[rule["id"]] = {"matches": 0, "unique_ips": 0, "ips": set()}
    for log_path in logs:
        try:
            with open(log_path, "r", encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError:
            continue
        for line in lines:
            tokens = line.split()
            for rule in rules:
                kw = rule["keyword"]
                if kw is None or kw not in tokens:
                    continue
                ip = None
                for tok in tokens:
                    if tok.startswith("from="):
                        rest = tok[len("from="):]
                        if ip is None and rest:
                            ip = rest
                        if rest:
                            stats[rule["id"]]["ips"].add(rest)
                stats[rule["id"]]["matches"] += 1
                events.append({"rule": rule["id"], "ip": ip, "line": line})
    for rid in stats:
        stats[rid]["ips"] = sorted(stats[rid]["ips"])
        stats[rid]["unique_ips"] = len(stats[rid]["ips"])
    return events, stats


def ref_expected(rules_path, logs):
    rules = ref_load_rules(rules_path)
    events, stats = ref_scan(rules, logs)
    alerts = [
        {"id": r["id"], "severity": r["severity"],
         "matches": stats[r["id"]]["matches"], "ips": stats[r["id"]]["ips"]}
        for r in rules if stats[r["id"]]["matches"] >= r["threshold"]
    ]
    alerts.sort(key=lambda a: a["id"])
    return {"alerts": alerts}, {"events": events, "statistics": stats}


# ---------- schema validation ----------
def check_alert_schema(alert):
    assert isinstance(alert, dict), "alert.json is not an object"
    assert set(alert.keys()) == {"timestamp", "alerts"}, alert.keys()
    assert isinstance(alert["timestamp"], str) and TS_RE.match(alert["timestamp"]), alert["timestamp"]
    alerts = alert["alerts"]
    assert isinstance(alerts, list), "alerts is not a list"
    ids = []
    for a in alerts:
        assert isinstance(a, dict) and set(a.keys()) == {"id", "severity", "matches", "ips"}, a
        assert isinstance(a["id"], str) and isinstance(a["severity"], str), a
        assert isinstance(a["matches"], int) and not isinstance(a["matches"], bool), a
        assert isinstance(a["ips"], list) and all(isinstance(x, str) for x in a["ips"]), a
        assert a["ips"] == sorted(set(a["ips"])), a
        ids.append(a["id"])
    assert ids == sorted(ids), "alerts not sorted by id"


def check_report_schema(rep):
    assert isinstance(rep, dict), "report.json is not an object"
    assert set(rep.keys()) == {"timestamp", "events", "statistics"}, rep.keys()
    assert isinstance(rep["timestamp"], str) and TS_RE.match(rep["timestamp"]), rep["timestamp"]
    assert isinstance(rep["events"], list), "events is not a list"
    for e in rep["events"]:
        assert isinstance(e, dict) and set(e.keys()) == {"rule", "ip", "line"}, e
        assert isinstance(e["rule"], str) and isinstance(e["line"], str), e
        assert e["ip"] is None or isinstance(e["ip"], str), e
    stats = rep["statistics"]
    assert isinstance(stats, dict), "statistics is not an object"
    for rid, s in stats.items():
        assert isinstance(s, dict) and set(s.keys()) == {"matches", "unique_ips", "ips"}, s
        assert isinstance(s["matches"], int) and isinstance(s["unique_ips"], int), s
        assert isinstance(s["ips"], list) and all(isinstance(x, str) for x in s["ips"]), s
        assert s["unique_ips"] == len(s["ips"]), s
        assert s["ips"] == sorted(set(s["ips"])), s
    rules_in_events = {e["rule"] for e in rep["events"]}
    for rid in rules_in_events:
        assert rid in stats, "event for unknown rule %r" % rid


def norm_alert(alert):
    return [(a["id"], a["severity"], a["matches"], tuple(a["ips"]))
            for a in alert["alerts"]]


def norm_report(rep):
    return ([(e["rule"], e["ip"], e["line"]) for e in rep["events"]],
            {k: (v["matches"], v["unique_ips"], tuple(v["ips"]))
             for k, v in rep["statistics"].items()})


def run_and_compare(rules_path, logs):
    for out in (ALERT_OUT, REPORT_OUT):
        if os.path.exists(out):
            os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, PROG, rules_path] + list(logs),
            capture_output=True, text=True, timeout=120,
        )
    except Exception as e:
        return "triage.py failed to run: %r" % e
    if r.returncode != 0:
        return "triage.py exited %d: %s" % (r.returncode, r.stderr[-300:])
    if not (os.path.isfile(ALERT_OUT) and os.path.isfile(REPORT_OUT)):
        return "missing /app/alert.json or /app/report.json after run"
    try:
        with open(ALERT_OUT) as f:
            alert = json.load(f)
        with open(REPORT_OUT) as f:
            report = json.load(f)
    except Exception as e:
        return "output json unreadable: %r" % e
    try:
        check_alert_schema(alert)
        check_report_schema(report)
    except AssertionError as e:
        return "schema violation: %s" % e
    exp_alert, exp_report = ref_expected(rules_path, logs)
    if norm_alert(alert) != norm_alert(exp_alert):
        return "alerts mismatch for %s" % rules_path
    if norm_report(report) != norm_report(exp_report):
        return "report mismatch for %s" % rules_path
    return None


failures = []
if no_modify_broken:
    failures.append("visible logs modified or missing (no-modify rule)")

if not os.path.isfile(PROG):
    failures.append("missing /app/triage.py")
else:
    # --- /app/rules.json must be valid JSON with the five required rule ids ---
    required_ids = {"port_probe", "dns_tunnel", "cred_stuffing", "beacon_1s", "noisy_scan"}
    try:
        with open("/app/rules.json") as f:
            authored = json.load(f)
        ids = {r.get("id") for r in authored.get("rules", []) if isinstance(r, dict)}
        if not required_ids.issubset(ids):
            failures.append("rules.json missing required rule ids: %s"
                            % sorted(required_ids - ids))
    except Exception as e:
        failures.append("rules.json invalid: %r" % e)

    # --- visible case: run with NO args on the supplied defaults ---
    if not os.path.isfile("/app/rules.json") or not (
            os.path.isfile("/app/logs/gateway.log")
            and os.path.isfile("/app/logs/dns.log")):
        failures.append("visible inputs missing")
    else:
        err = run_and_compare("/app/rules.json",
                              ["/app/logs/gateway.log", "/app/logs/dns.log"])
        if err:
            failures.append("visible case: " + err)

    # --- hidden cases ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            rules_p = os.path.join(base, "rules.json")
            if not os.path.isfile(rules_p):
                failures.append("hidden '%s' malformed (no rules.json)" % c)
                continue
            logs = sorted(
                os.path.join(base, n)
                for n in os.listdir(base)
                if n != "rules.json" and os.path.isfile(os.path.join(base, n))
            )
            if not logs:
                failures.append("hidden '%s' has no log files" % c)
                continue
            err = run_and_compare(rules_p, logs)
            if err:
                failures.append("hidden '%s': %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
