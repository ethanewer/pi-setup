#!/bin/bash
# Verifier for cinder-vale: checks the visible deliverables byte-exactly,
# re-executes /app/solve.py (0-arg form on /app, 1-arg form on every hidden
# workdir), and compares its emitted artifacts against expected outputs.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import os, shutil, subprocess, sys, tempfile

SOLVE = "/app/solve.py"
failures = []


def read_bytes(p):
    with open(p, "rb") as fh:
        return fh.read()


def check_schedule(got_path, want_path, label):
    try:
        with open(got_path, newline="") as fh:
            got = [ln.strip() for ln in fh if ln.strip()]
        with open(want_path, newline="") as fh:
            want = [ln.strip() for ln in fh if ln.strip()]
    except Exception as e:
        failures.append("%s unreadable: %s" % (label, e))
        return
    if not got or got[0] != "id,finish":
        failures.append("%s: bad header" % label)
        return
    if got[1:] != want[1:]:
        failures.append("%s: rows differ: %r vs %r" % (label, got[1:], want[1:]))


def check_basket(workdir, expdir, label):
    plans = os.path.join(workdir, "plans.jsonl")
    answer = os.path.join(workdir, "answer.json")
    sched = os.path.join(workdir, "schedule.csv")
    if not all(os.path.isfile(p) for p in (plans, answer, sched)):
        failures.append("%s: missing emitted artifact(s)" % label)
        return
    try:
        if read_bytes(plans) != read_bytes(os.path.join(expdir, "plans.jsonl")):
            failures.append("%s: plans.jsonl bytes differ" % label)
        if read_bytes(answer) != read_bytes(os.path.join(expdir, "answer.json")):
            failures.append("%s: answer.json differs" % label)
    except Exception as e:
        failures.append("%s: compare failed: %s" % (label, e))
        return
    check_schedule(sched, os.path.join(expdir, "schedule.csv"), label)


# --- deliverable presence
if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- 1. deliverable presence at the declared /app paths
    for p in ("/app/plans.jsonl", "/app/answer.json", "/app/schedule.csv"):
        if not os.path.isfile(p):
            failures.append("missing deliverable %s" % p)

    # --- 2. agent-produced visible artifacts must already match
    check_basket("/app", "/tests/expected", "visible-pre")

    # --- 2. re-execute 0-argument form on /app and re-check
    try:
        r = subprocess.run([sys.executable, SOLVE], capture_output=True,
                           text=True, timeout=120)
    except Exception as e:
        r = None
        failures.append("0-arg run raised: %s" % e)
    if r is not None:
        if r.returncode != 0:
            failures.append("0-arg run exited %d: %s" % (r.returncode, r.stderr[-400:]))
        else:
            check_basket("/app", "/tests/expected", "visible-rerun")

    # --- 3. hidden workdirs, 1-argument form
    hidden = "/tests/hidden"
    if not os.path.isdir(hidden):
        failures.append("no hidden cases present")
    else:
        for case in sorted(os.listdir(hidden)):
            cdir = os.path.join(hidden, case)
            jobs = os.path.join(cdir, "jobs.csv")
            if not os.path.isfile(jobs):
                failures.append("hidden '%s': no jobs.csv" % case)
                continue
            tmp = tempfile.mkdtemp(prefix="cv_case_")
            try:
                os.makedirs(os.path.join(tmp, "input"))
                shutil.copy(jobs, os.path.join(tmp, "input", "jobs.csv"))
                r = subprocess.run([sys.executable, SOLVE, tmp],
                                   capture_output=True, text=True, timeout=120)
                if r.returncode != 0:
                    failures.append("hidden '%s': exit %d: %s"
                                    % (case, r.returncode, r.stderr[-400:]))
                else:
                    check_basket(tmp, cdir, "hidden-'%s'" % case)
            except Exception as e:
                failures.append("hidden '%s': %s" % (case, e))
            finally:
                shutil.rmtree(tmp, ignore_errors=True)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
