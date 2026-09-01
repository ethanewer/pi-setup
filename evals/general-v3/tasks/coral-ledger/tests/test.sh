#!/bin/bash
# Verifier for coral-ledger: ENFORCES data-file immutability (sha256 of
# /app/data/port.db before/after the agent program runs, plus absence of
# WAL/SHM/journal sidecars), then EXECUTES /app/solve.py on the visible
# ledger and on hidden ledgers and compares the answers. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the shipped visible ledger.
PRISTINE_DB_SHA="$(sha256sum /app/data/port.db 2>/dev/null | awk '{print $1}')"

python3 - "$PRISTINE_DB_SHA" <<'PY'
import glob, hashlib, json, os, shutil, subprocess, sys

pristine = sys.argv[1]
failures = []

DB = "/app/data/port.db"
SOLVE = "/app/solve.py"
OUT = "/tmp/coral_ledger_answer.json"

SIDEARS = [DB + "-wal", DB + "-shm", DB + "-journal", DB + "-journal-wal"]


def db_sha():
    try:
        with open(DB, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


def clean_sidcars():
    for p in SIDEARS:
        try:
            if os.path.exists(p):
                os.remove(p)
                return True
        except OSError:
            pass
    return False


def norm(ans):
    """Tolerant normalization; never raises on malformed agent output."""
    try:
        assert isinstance(ans, dict), "not a dict"
        assert set(ans.keys()) == {"dwell_by_port", "top_commodity",
                                   "duplicate_bol", "flag_mix",
                                   "idle_vessels"}, sorted(ans.keys())
        dwell = {str(k): round(float(v), 2)
                 for k, v in ans["dwell_by_port"].items()}
        tc = ans["top_commodity"]
        assert isinstance(tc, dict) and set(tc) >= {"commodity", "total_tons"}, tc
        top = (str(tc["commodity"]), int(tc["total_tons"]))
        dup = ans["duplicate_bol"]
        assert isinstance(dup, dict), dup
        dups = (int(dup["bols"]), int(dup["excess_rows"]))
        mix = [(str(f), int(n)) for f, n in ans["flag_mix"]]
        idle = [str(n) for n in ans["idle_vessels"]]
        return (dwell, top, dups, mix, idle)
    except Exception as e:
        raise AssertionError("malformed answer: %s" % e)


def run_case(db_path, expected_path, workdir=None):
    if os.path.exists(OUT):
        os.remove(OUT)
    try:
        r = subprocess.run([sys.executable, SOLVE, db_path, OUT],
                           capture_output=True, text=True, timeout=180,
                           cwd=workdir or "/app")
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(OUT):
        return False
    try:
        with open(OUT) as fh:
            got = json.load(fh)
        with open(expected_path) as fh:
            want = json.load(fh)
        return norm(got) == norm(want)
    except Exception:
        return False


if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible ledger, in place, with immutability enforcement ---------
    if pristine is None or pristine == "":
        failures.append("visible ledger missing")
    else:
        if not run_case(DB, "/tests/expected.json"):
            failures.append("visible case failed")
        after = db_sha()
        if after != pristine:
            failures.append("visible ledger was modified (sha mismatch)")
        if clean_sidcars():
            failures.append("sidecar journal/WAL file created next to ledger")
        # answer.json deliverable must match the visible reference
        try:
            with open("/app/answer.json") as fh:
                got = json.load(fh)
            with open("/tests/expected.json") as fh:
                want = json.load(fh)
            if norm(got) != norm(want):
                failures.append("/app/answer.json does not match reference")
        except Exception:
            failures.append("/app/answer.json missing or unreadable")

    # --- hidden ledgers: fresh copies, same immutability rule ------------
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            db = os.path.join(base, "port.db")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(db) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            scratch = "/tmp/coral_ledger_cases/%s.db" % c
            try:
                os.makedirs("/tmp/coral_ledger_cases", exist_ok=True)
                shutil.copyfile(db, scratch)
            except Exception:
                failures.append("hidden '%s' unreadable" % c)
                continue
            before = hashlib.sha256(open(scratch, "rb").read()).hexdigest()
            if not run_case(scratch, exp, workdir="/tmp"):
                failures.append("hidden case '%s' failed" % c)
            after = hashlib.sha256(open(scratch, "rb").read()).hexdigest()
            if after != before:
                failures.append("hidden ledger '%s' was modified" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
