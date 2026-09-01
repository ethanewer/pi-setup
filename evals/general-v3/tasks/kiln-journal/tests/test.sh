#!/bin/bash
# Verifier for kiln-journal: checks the visible merged artifacts, re-executes
# /app/solve.py on every hidden scenario directory (each with its own expected
# merged set), and enforces the no-modify rule on scenario inputs. Writes REWARD
# (0/1) to /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/solve.py ]; then
  echo "missing /app/solve.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import hashlib, json, os, shutil, sqlite3, subprocess, sys, tempfile

FAIL = []


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def rows_of(db_path):
    conn = sqlite3.connect(db_path)
    try:
        return [list(r) for r in conn.execute(
            "SELECT id, sensor, celsius, taken_on FROM readings ORDER BY id")]
    finally:
        conn.close()


def same_rows(got, want):
    if not isinstance(got, list) or len(got) != len(want):
        return False
    for g, w in zip(got, want):
        if len(g) != 4 or len(w) != 4:
            return False
        for a, b in zip(g, w):
            if isinstance(a, (int, float)) and isinstance(b, (int, float)):
                if abs(float(a) - float(b)) > 1e-9:
                    return False
            elif a != b:
                return False
    return True


def load_expected(path):
    try:
        return json.load(open(path))
    except Exception:
        return None


def norm_json(path):
    try:
        obj = json.load(open(path))
    except Exception:
        return None
    if not isinstance(obj, dict) or "count" not in obj or "rows" not in obj:
        return None
    return obj


def run_solver(in_dir, out_dir):
    r = subprocess.run([sys.executable, "/app/solve.py", in_dir, out_dir],
                       capture_output=True, text=True, timeout=180)
    return r


def check_case(in_dir, expected_path, label):
    exp = load_expected(expected_path)
    if exp is None:
        FAIL.append("%s: expected fixture unreadable" % label)
        return
    # record input hashes for the no-modify rule
    inputs = sorted(
        os.path.join(dp, f)
        for dp, _, fs in os.walk(in_dir) for f in fs
    )
    before = {p: sha(p) for p in inputs}

    out = tempfile.mkdtemp(prefix="kiln_verify_")
    try:
        r = run_solver(in_dir, out)
        if r.returncode != 0:
            FAIL.append("%s: solver exit=%d" % (label, r.returncode))
            return
        mdb = os.path.join(out, "merged.db")
        mjs = os.path.join(out, "merged.json")
        if not os.path.isfile(mdb):
            FAIL.append("%s: missing merged.db" % label)
            return
        try:
            got_rows = rows_of(mdb)
        except Exception as e:
            FAIL.append("%s: merged.db unreadable: %r" % (label, e))
            return
        if not same_rows(got_rows, exp.get("rows", [])):
            FAIL.append("%s: merged.db rows mismatch (got %d want %d)"
                        % (label, len(got_rows), len(exp.get("rows", []))))
        js = norm_json(mjs)
        if js is None:
            FAIL.append("%s: merged.json unreadable/malformed" % label)
        elif js.get("count") != len(js.get("rows", [])) or not same_rows(
                js.get("rows", []), exp.get("rows", [])):
            FAIL.append("%s: merged.json mismatch" % label)
        # no-modify rule
        for p in inputs:
            if not os.path.exists(p) or sha(p) != before.get(p):
                FAIL.append("%s: input file modified: %s" % (label, os.path.basename(p)))
    finally:
        shutil.rmtree(out, ignore_errors=True)


# ---------- visible case: /app deliverables must match the expected merge ----------
exp_vis = load_expected("/tests/expected_visible.json")
if exp_vis is None:
    FAIL.append("visible expected fixture unreadable")
else:
    if not os.path.isfile("/app/merged.db"):
        FAIL.append("missing /app/merged.db")
    else:
        try:
            if not same_rows(rows_of("/app/merged.db"), exp_vis.get("rows", [])):
                FAIL.append("visible merged.db rows mismatch")
        except Exception as e:
            FAIL.append("visible merged.db unreadable: %r" % e)
    js = norm_json("/app/merged.json")
    if js is None:
        FAIL.append("missing/malformed /app/merged.json")
    elif not same_rows(js.get("rows", []), exp_vis.get("rows", [])) or \
            js.get("count") != len(js.get("rows", [])):
        FAIL.append("visible merged.json mismatch")

# visible input must be unmodified too
for p in ("/app/telemetry.db", "/app/journal/telemetry.wal"):
    if not os.path.isfile(p):
        FAIL.append("visible input missing: %s" % p)

# ---------- hidden scenarios ----------
HID = "/tests/hidden"
if os.path.isdir(HID):
    cases = [c for c in sorted(os.listdir(HID))
             if os.path.isfile(os.path.join(HID, c, "expected.json"))]
    if not cases:
        FAIL.append("no hidden scenarios found")
    for c in cases:
        check_case(os.path.join(HID, c), os.path.join(HID, c, "expected.json"), c)

print("verify failures:", FAIL)
with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1" if not FAIL else "0")
sys.exit(0)
PY
