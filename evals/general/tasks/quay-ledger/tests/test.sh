#!/bin/bash
# Verifier for quay-ledger (executes-deliverable). Requires /app/solve.py.
# Re-runs the solver on the visible scenario (/app) and on every hidden
# scenario directory in /tests/hidden, then checks loaded.db schema+rows,
# load_report.json, and the .import statement evidence in import_log.txt.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

if [ ! -f /app/solve.py ]; then
  echo "missing /app/solve.py -> 0" >&2
  exit 0
fi

python3 - <<'PY'
import json, os, re, sqlite3, subprocess, sys


def close(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) <= 1e-6
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(close(x, y) for x, y in zip(a, b))
    return a == b


def check_case(in_dir, expected_path, label, fails):
    out = "/tmp/chk_" + label
    subprocess.run(["rm", "-rf", out], shell=False)
    os.makedirs(out)
    try:
        exp = json.load(open(expected_path))
    except Exception:
        fails.append("%s:no-expected" % label)
        return
    try:
        r = subprocess.run(["python3", "/app/solve.py", in_dir, out],
                           capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            fails.append("%s:exit:%s:%s" % (label, r.returncode,
                                            r.stderr[-300:]))
    except Exception as e:
        fails.append("%s:exec:%s" % (label, e))

    db = os.path.join(out, "loaded.db")
    rep = os.path.join(out, "load_report.json")
    log = os.path.join(out, "import_log.txt")
    for p in (db, rep, log):
        if not os.path.exists(p):
            fails.append("%s:missing:%s" % (label, os.path.basename(p)))
    if fails and fails[-1].startswith("%s:missing" % label):
        return

    # schema check (names, types, notnull, pk)
    try:
        con = sqlite3.connect(db)
        cols = [[c[1], c[2], c[3], c[5]]
                for c in con.execute("PRAGMA table_info('readings')")]
        if not close(cols, exp["schema"]):
            fails.append("%s:schema:%s" % (label, cols))
        rows = con.execute(
            "SELECT station_id, region, observed_on, temp_c, humidity "
            "FROM readings ORDER BY station_id").fetchall()
        rows = [[int(a), b, c, round(float(d), 6), round(float(e), 6)]
                for a, b, c, d, e in rows]
        if not close(rows, exp["rows"]):
            fails.append("%s:rows" % label)
        con.close()
    except Exception as e:
        fails.append("%s:db:%s" % (label, e))
        return

    # report check
    try:
        rep_json = json.load(open(rep))
        assert isinstance(rep_json, dict), type(rep_json)
        if not close(int(rep_json.get("rows_loaded", -1)), exp["rows_loaded"]):
            fails.append("%s:rows_loaded:%s" % (label, rep_json.get("rows_loaded")))
        if not close(list(rep_json.get("regions", [])), exp["regions"]):
            fails.append("%s:regions:%s" % (label, rep_json.get("regions")))
        if not isinstance(rep_json.get("regions", None), list):
            fails.append("%s:regions-type" % label)
    except Exception as e:
        fails.append("%s:report:%s" % (label, e))

    # statement-evidence check: the load must have gone through .import
    try:
        txt = open(log).read()
        if not txt.strip() or not re.search(r"\.import\b", txt):
            fails.append("%s:import-log-evidence" % label)
    except Exception:
        fails.append("%s:import-log-unreadable" % label)

    subprocess.run(["rm", "-rf", out], shell=False)


fails = []

# visible scenario (inputs are /app, deliverables in /app too)
check_case("/app", "/tests/expected.json", "visible", fails)

# the shipped /app deliverables must themselves be present and correct
for _art in ("/app/loaded.db", "/app/load_report.json", "/app/import_log.txt"):
    if not os.path.exists(_art):
        fails.append("visible:no-artifact:" + os.path.basename(_art))
try:
    _rep = json.load(open("/app/load_report.json"))
    if not isinstance(_rep, dict) or "rows_loaded" not in _rep:
        fails.append("visible:load-report-json")
except Exception:
    fails.append("visible:load-report-json")
try:
    _txt = open("/app/import_log.txt").read()
    if not _txt.strip() or not re.search(r"\.import\b", _txt):
        fails.append("visible:import-log-evidence")
except Exception:
    fails.append("visible:import-log-evidence")

# hidden scenarios (read-only inputs, fresh writable output dir)
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    for name in sorted(os.listdir(hidden)):
        d = os.path.join(hidden, name)
        if not os.path.isdir(d):
            continue
        check_case(d, os.path.join(d, "expected.json"), name, fails)

reward = "1" if not fails else "0"
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write(reward + "\n")
if fails:
    print("FAILURES:", fails, file=sys.stderr)
print("reward=" + reward)
PY
