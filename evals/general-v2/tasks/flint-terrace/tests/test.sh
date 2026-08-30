#!/bin/bash
# Verifier for flint-terrace (executes-deliverable).
# Requires /app/solve.py. Re-runs the solver on the visible scenario and on
# each hidden scenario directory, and compares every artifact to expectations.
# Writes REWARD (0 or 1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/solve.py ]; then
  echo "missing /app/solve.py (pristine) -> 0" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json, os, subprocess, sqlite3

def close(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, str) or isinstance(b, str):
        return a == b
    if a is None or b is None:
        return a is None and b is None
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) <= 1e-6
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a) == set(b) and all(close(a[k], b[k]) for k in b)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(close(x, y) for x, y in zip(a, b))
    return a == b


def run_solver(in_dir, outdir):
    subprocess.run(["python3", "/app/solve.py", in_dir, outdir],
                   capture_output=True, text=True)


def check_case(in_dir, expected_path, label, fails):
    out = "/tmp/" + "chk_" + label
    subprocess.run(["rm", "-rf", out], shell=False)
    os.makedirs(out)
    try:
        expected = json.load(open(expected_path))
    except Exception:
        fails.append("%s:no-expected" % label)
        return
    exp = expected
    try:
        run_solver(in_dir, out)
    except Exception:
        pass
    base = out
    need = ["schema.sql", "recovered.db", "salvage.json", "summary.sql",
            "fixed_query.sql", "import_log.txt"]
    missing = [n for n in need if not os.path.exists(os.path.join(base, n))]
    if missing:
        fails.append("%s:missing:%s" % (label, ",".join(missing)))
        return

    db = os.path.join(base, "recovered.db")
    try:
        con = sqlite3.connect(db)

        rows = con.execute(
            "SELECT id,domain,site,recorded_on,reading FROM catalog ORDER BY id"
        ).fetchall()
        rows = [[int(a), b, c, d, round(float(e), 6)] for a, b, c, d, e in rows]
        if not close(rows, exp.get("recovered", [])):
            fails.append("%s:recovered" % label)

        got = con.execute(open(os.path.join(base, "summary.sql")).read()).fetchall()
        got = [[r[0], int(r[1])] for r in got]
        if not close(got, exp.get("summary", [])):
            fails.append("%s:summary" % label)

        cols = [[r[1], r[2]] for r in con.execute("PRAGMA table_info('catalog')")]
        if not close(cols, exp.get("schema", [])):
            fails.append("%s:schema" % label)
        con.close()
    except Exception:
        fails.append("%s:recovered-db" % label)

    try:
        sal = json.load(open(os.path.join(base, "salvage.json")))["salvaged"]
        if not close(sal, exp.get("salvage", [])):
            fails.append("%s:salvage" % label)
    except Exception:
        fails.append("%s:salvage" % label)

    try:
        rref = sqlite3.connect(os.path.join(in_dir, "ref.db"))
        rows = rref.execute(open(os.path.join(base, "fixed_query.sql")).read()).fetchall()
        rows = [[f if not isinstance(f, float) else round(f, 6) for f in row]
                for row in rows]
        if not close(rows, exp.get("fixed", [])):
            fails.append("%s:fixed" % label)
        rref.close()
    except Exception:
        fails.append("%s:fixed" % label)

    log = ""
    try:
        log = open(os.path.join(base, "import_log.txt")).read()
    except Exception:
        pass
    if not (log.strip() and
            any(k in log.lower() for k in ("copy", "import"))):
        fails.append("%s:import_log" % label)

    subprocess.run(["rm", "-rf", out], shell=False)


fails = []

# visible case (inputs are /app, deliverables in /app too)
check_case("/app", "/tests/expected.json", "visible", fails)

# additionally: the shipped /app deliverables must themselves be present
for _art in ("/app/schema.sql", "/app/recovered.db", "/app/salvage.json",
             "/app/summary.sql", "/app/fixed_query.sql",
             "/app/import_log.txt"):
    if not os.path.exists(_art):
        fails.append("visible:no-artifact:" + os.path.basename(_art))

# validate the shipped /app artifacts directly (proves the declared
# /app deliverables are the ones the verifier consumes)
try:
    _sal = json.load(open("/app/salvage.json"))
    if not isinstance(_sal, dict) or "salvaged" not in _sal:
        fails.append("visible:salvage-json")
except Exception:
    fails.append("visible:salvage-json")

try:
    _con = sqlite3.connect("/app/recovered.db")
    _sum = _con.execute(
        open("/app/summary.sql").read()).fetchall()
    _con.close()
except Exception:
    fails.append("visible:summary-sql")

try:
    _con = sqlite3.connect("/app/ref.db")
    _con.execute(open("/app/fixed_query.sql").read()).fetchall()
    _con.close()
except Exception:
    fails.append("visible:fixed-query-sql")

try:
    _log = open("/app/import_log.txt").read()
    if not (_log.strip() and
            any(k in _log.lower() for k in ("copy", "import"))):
        fails.append("visible:import-log")
except Exception:
    fails.append("visible:import-log")

# hidden cases
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    for name in sorted(os.listdir(hidden)):
        case = os.path.join(hidden, name)
        if not os.path.isdir(case):
            continue
        check_case(case, os.path.join(case, "expected.json"),
                   "hidden-" + name, fails)

if fails:
    print("FAILS: %d\n%s" % (len(fails), "\n".join(" - " + f for f in fails)))
    reward = "0"
else:
    print("ALL CHECKS PASSED")
    reward = "1"

open("/logs/verifier/reward.txt", "w").write(reward + "\n")
PY