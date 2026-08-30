#!/bin/bash
# Verifier for kestrel-vault: ENFORCES no-modify on the shipped game fixtures,
# checks the visible deliverables (/app/ending.txt, /app/state/vault.db), and
# EXECUTES the deliverable driver (/app/solve.py) on hidden vault scenarios,
# checking the captured ending and the flushed database after each run.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of shipped fixtures (instruction forbids modification).
WANT_GAME_SHA="7c941e6e5023b8d891b83431d786bb77e672e19ed74b0a056672ce9bd9655b0e"
WANT_SCEN_SHA="e06336dfa42c73088af892c5137004e8c39609a653c8bd8438a090b9f4f37b5e"

no_modify_broken=0
if [ ! -f /app/vault.py ]; then
    echo "no-modify: /app/vault.py missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/vault.py | awk '{print $1}')"
    [ "$actual" != "$WANT_GAME_SHA" ] && { echo "no-modify: /app/vault.py was modified" >&2; no_modify_broken=1; }
fi
if [ ! -f /app/scenario.json ]; then
    echo "no-modify: /app/scenario.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/scenario.json | awk '{print $1}')"
    [ "$actual" != "$WANT_SCEN_SHA" ] && { echo "no-modify: /app/scenario.json was modified" >&2; no_modify_broken=1; }
fi

python3 - "$no_modify_broken" <<'PY'
import json
import os
import sqlite3
import subprocess
import sys
import tempfile

no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("game fixtures modified or missing")

GAME = "/app/vault.py"
SOLVE = "/app/solve.py"


def check_db(db_path, n_containers):
    """Return an error string or None; requires a flushed session with a
    successful seal and per-gem place events."""
    if not os.path.isfile(db_path):
        return "database %s missing (state was never flushed)" % db_path
    try:
        conn = sqlite3.connect(db_path)
        rows = conn.execute(
            "SELECT keeper, gems_found, gems_placed, moves, completed FROM sessions"
        ).fetchall()
        if len(rows) != 1:
            conn.close()
            return "expected exactly 1 session row, got %d" % len(rows)
        keeper, found, placed, moves, completed = rows[0]
        if not keeper:
            conn.close()
            return "session row has empty keeper"
        if completed != 1:
            conn.close()
            return "session completed != 1"
        if placed != n_containers or found != n_containers:
            conn.close()
            return "gems_placed/found != %d" % n_containers
        if moves < n_containers * 2 + 2:
            conn.close()
            return "suspiciously low move count"
        ev = conn.execute(
            "SELECT kind, detail FROM events WHERE session_id = 1"
        ).fetchall()
        conn.close()
        kinds = [k for (k, d) in ev]
        if kinds.count("place") < n_containers:
            return "expected >= %d place events, got %d" % (n_containers, kinds.count("place"))
        if ("seal", "ok") not in ev:
            return "no successful seal event"
        return None
    except sqlite3.Error as e:
        return "database unreadable: %s" % e


def run_case(scenario_path, expected_ending, workdir, tag):
    out = os.path.join(workdir, "ending.txt")
    db = os.path.join(workdir, "state.db")
    for p in (out, db):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run(
        [sys.executable, SOLVE, GAME, scenario_path, out, db],
        capture_output=True, text=True, timeout=180,
    )
    if r.returncode != 0:
        return "%s: driver exited %d" % (tag, r.returncode)
    if not os.path.isfile(out):
        return "%s: ending output missing" % tag
    with open(out, encoding="utf-8") as fh:
        got = fh.read()
    if got != expected_ending:
        return "%s: ending message mismatch" % tag
    try:
        with open(scenario_path, encoding="utf-8") as fh:
            sc = json.load(fh)
    except Exception:
        return "%s: scenario unreadable" % tag
    err = check_db(db, len(sc["containers"]))
    if err:
        return "%s: %s" % (tag, err)
    return None


if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case ---
    try:
        with open("/app/scenario.json", encoding="utf-8") as fh:
            sc = json.load(fh)
        ending = sc["ending"]
        n = len(sc["containers"])
    except Exception:
        ending = None
        n = 0
        failures.append("shipped scenario unreadable")

    if ending is not None:
        # /app/ending.txt deliverable
        if not os.path.isfile("/app/ending.txt"):
            failures.append("missing /app/ending.txt")
        else:
            with open("/app/ending.txt", encoding="utf-8") as fh:
                if fh.read() != ending:
                    failures.append("/app/ending.txt does not match the true ending message")
        # /app/state/vault.db deliverable (flushed by a clean quit)
        err = check_db("/app/state/vault.db", n)
        if err:
            failures.append("visible db: " + err)

        # re-execute the driver on the visible scenario into fresh paths
        work = tempfile.mkdtemp(prefix="kv_vis_")
        err = run_case("/app/scenario.json", ending, work, "visible")
        if err:
            failures.append(err)

    # --- hidden cases ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            scen = os.path.join(base, "scenario.json")
            if not os.path.isfile(scen):
                failures.append("hidden '%s' malformed" % c)
                continue
            try:
                with open(scen, encoding="utf-8") as fh:
                    expected_ending = json.load(fh)["ending"]
            except Exception:
                failures.append("hidden '%s': bad scenario" % c)
                continue
            work = tempfile.mkdtemp(prefix="kv_hid_")
            err = run_case(scen, expected_ending, work, "hidden '%s'" % c)
            if err:
                failures.append(err)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
