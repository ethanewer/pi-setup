#!/bin/bash
# Verifier for pumice-berth (executes-deliverable).
# Requires /app/solve.py. Re-runs the solver on the visible scenario (/app) and
# on each hidden scenario directory, checks loaded.db / summary.json against
# expectations, and enforces the client-copy (.import) statement evidence in
# import_log.txt. Writes REWARD (0 or 1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/solve.py ]; then
  echo "missing /app/solve.py (pristine) -> 0" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json, os, shutil, sqlite3, subprocess

SOLVER = "/app/solve.py"
failures = []


def check_case(in_dir, expected_path, out_dir, label):
    try:
        expected = json.load(open(expected_path))
    except Exception as e:
        failures.append("%s:unreadable-expected:%r" % (label, e))
        return
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir, exist_ok=True)
    try:
        r = subprocess.run(["python3", SOLVER, in_dir, out_dir],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            failures.append("%s:solver-failed-rc:%s" % (label, r.returncode))
            return
    except Exception as e:
        failures.append("%s:solver-exception:%r" % (label, e))
        return

    db = os.path.join(out_dir, "loaded.db")
    log_path = os.path.join(out_dir, "import_log.txt")
    sum_path = os.path.join(out_dir, "summary.json")

    # database contents + schema
    try:
        con = sqlite3.connect(db)
        rows = con.execute(
            "SELECT id,sensor,metric,value,recorded_on FROM readings ORDER BY id"
        ).fetchall()
        rows = [[int(a), b, c, round(float(d), 6), e] for a, b, c, d, e in rows]
        if rows != expected["rows"]:
            failures.append("%s:rows-mismatch" % label)
        cols = [[c[1], c[2]] for c in con.execute("PRAGMA table_info('readings')")]
        if cols != [["id", "INTEGER"], ["sensor", "TEXT"], ["metric", "TEXT"],
                    ["value", "REAL"], ["recorded_on", "TEXT"]]:
            failures.append("%s:schema-mismatch:%s" % (label, cols))
        con.close()
    except Exception as e:
        failures.append("%s:db-check-exception:%r" % (label, e))

    # summary aggregates
    try:
        got = json.load(open(sum_path))
        want = expected["summary"]
        ok = (got.get("total_rows") == want["total_rows"]
              and got.get("min_recorded_on") == want["min_recorded_on"]
              and got.get("max_recorded_on") == want["max_recorded_on"]
              and set(got.get("by_metric", {})) == set(want["by_metric"])
              and all(got["by_metric"][k] == want["by_metric"][k]
                      for k in want["by_metric"])
              and set(got.get("avg_value_by_metric", {})) == set(want["avg_value_by_metric"])
              and all(abs(float(got["avg_value_by_metric"][k]) - float(want["avg_value_by_metric"][k])) <= 1e-6
                      for k in want["avg_value_by_metric"]))
        if not ok:
            failures.append("%s:summary-mismatch" % label)
    except Exception as e:
        failures.append("%s:summary-exception:%r" % (label, e))

    # client-copy statement evidence
    try:
        log = open(log_path).read()
        n = expected["summary"]["total_rows"]
        if not (".import" in log
                and "readings.csv" in log
                and ("loaded_rows: %d" % n) in log):
            failures.append("%s:import-log-evidence" % label)
    except Exception as e:
        failures.append("%s:import-log-exception:%r" % (label, e))


# visible case: solver runs on /app (in) and must (re)produce /app deliverables
for art in ("/app/loaded.db", "/app/import_log.txt", "/app/summary.json"):
    if not os.path.isfile(art):
        failures.append("missing visible deliverable %s" % art)
check_case("/app", "/tests/expected.json", "/tmp/chk_visible", "visible")

# hidden cases
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        if not all(os.path.isfile(os.path.join(base, f))
                   for f in ("readings.csv", "schema.sql", "expected.json")):
            failures.append("hidden '%s' malformed" % c)
            continue
        check_case(base, os.path.join(base, "expected.json"),
                   "/tmp/chk_%s" % c, c)
else:
    failures.append("no hidden case dir")

print("verify failures:", failures)
import sys
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
