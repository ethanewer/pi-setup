#!/bin/bash
# keelson-cairn verifier.
#
# Executes the deliverables (/app/kedd/build.sh, /app/kedd/run.sh) and proves
# the repaired daemon lifecycle: launch -> READY marker -> (still alive) ->
# SIGTERM -> exit within a generous bound -> journal complete, strictly
# ordered, digest-valid, on disk. Repeats across the visible sample workload
# and three hidden workloads (tests/hidden/H1..H3), each with different
# event counts, width profiles and payloads. A daemon whose shutdown path is
# not fixed hangs on SIGTERM and scores 0.
#
# Also runs the shipped semantic check suite (tests/check.sh) so a fix cannot
# break the parsing/digest/journaling machinery, and hash-pins every workload
# fixture so none of them can be replaced or weakened.
#
# Writes exactly 1 or 0 to /logs/verifier/reward.txt on every exit path.
set -u

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
mkdir -p /logs/verifier

python3 - <<'PY'
import hashlib
import os
import shutil
import signal
import subprocess
import sys
import time

BUILD = "/app/kedd/build.sh"
RUN = "/app/kedd/run.sh"
CHECK = "/app/kedd/tests/check.sh"
SAMPLE = "/app/kedd/workloads/sample/workload.txt"
HIDDEN = "/tests/hidden"

START_BOUND = 60.0     # seconds to wait for the READY marker
SIGTERM_DELAY = 1.0    # seconds between READY and the SIGTERM
# Generous exit bound: the correct repair exits in ~10-17s on a busy host
# (drain of the residual queue + one fsync per journaled line); 60s gives a
# >3x margin over the worst measured cold exit, and the broken daemon never
# exits at all, so the bound cleanly separates hang from repair.
EXIT_BOUND = 60.0      # seconds the daemon may take to exit after SIGTERM
ACCEPTED_RC = (0, 143)  # clean jvm exit / jvm terminated by the SIGTERM

# Each workload fixture is pinned so it cannot be replaced or weakened.
FIXTURE_SHA256 = {
    "/app/kedd/workloads/sample/workload.txt":
        "0695497865c4b1309feda02c396ea81bb5e85ab92390863bf847ad70ffbb98c9",
    "/tests/hidden/H1/workload.txt":
        "f3150fec38826eacd187dba1709d0547b5dcd034e6f2d433a0abc64682708a84",
    "/tests/hidden/H2/workload.txt":
        "18619684f38e6ce87afe25106754c5cad395d293e8ff15f1e3c7fb63ae060493",
    "/tests/hidden/H3/workload.txt":
        "185f302a727f28ecace56059bbac4f1a2a03124bda067b8bc29498c1fbc26e54",
}

failures = []


def fail(msg):
    failures.append(msg)


def sha256(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def parse_workload(path):
    """Returns ordered list of (ordinal, payload, width)."""
    events = []
    with open(path, "r", encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(",")
            if len(parts) != 3:
                raise ValueError("workload %s line %d: bad fields" % (path, lineno))
            ordinal, payload, width = int(parts[0]), parts[1], int(parts[2])
            if ordinal != len(events):
                raise ValueError("workload %s line %d: ordinal %d out of sequence"
                                 % (path, lineno, ordinal))
            events.append((ordinal, payload, width))
    return events


def expected_journal(events):
    out = []
    for ordinal, payload, width in events:
        digest = hashlib.sha256(
            ("%d:%s:%d" % (ordinal, payload, width)).encode("utf-8")
        ).hexdigest()[:16]
        out.append("%d|%s|%s" % (ordinal, payload, digest))
    return out


def run_case(tag, workload_path, workdir):
    """Launches the daemon on one workload and checks the full lifecycle.
    Returns (failures, exit_elapsed_seconds or None)."""
    case_fails = []
    shutil.rmtree(workdir, ignore_errors=True)
    os.makedirs(workdir)
    journal = os.path.join(workdir, "journal.txt")
    ready = os.path.join(workdir, "ready.txt")
    state = os.path.join(workdir, "state")
    logfile = os.path.join(workdir, "daemon.log")

    events = parse_workload(workload_path)
    want = expected_journal(events)

    with open(logfile, "wb") as log:
        proc = subprocess.Popen(
            ["bash", RUN, "--workload", workload_path,
             "--journal", journal, "--ready", ready, "--state", state],
            stdout=log, stderr=subprocess.STDOUT)

    # 1) Readiness within START_BOUND.
    deadline = time.time() + START_BOUND
    while time.time() < deadline:
        if os.path.isfile(ready):
            with open(ready, "r", encoding="utf-8", errors="replace") as fh:
                if fh.read().startswith("READY"):
                    break
        if proc.poll() is not None:
            break
        time.sleep(0.1)
    else:
        case_fails.append("no READY marker within %.0fs" % START_BOUND)

    if os.path.isfile(ready):
        with open(ready, "r", encoding="utf-8", errors="replace") as fh:
            ready_ok = fh.read().rstrip().startswith("READY")
    else:
        ready_ok = False

    if not ready_ok:
        if proc.poll() is not None:
            case_fails.append("daemon exited before readiness (rc=%s)"
                              % proc.returncode)
        else:
            proc.kill()
            proc.wait()
        case_fails.append("daemon never reported readiness")
        return case_fails, None

    # 2) The daemon must still be alive and processing when SIGTERM arrives:
    #    the workload is sized so that it cannot be drained in the delay.
    time.sleep(SIGTERM_DELAY)
    if proc.poll() is not None:
        case_fails.append("daemon exited on its own before SIGTERM "
                          "(workload must not be drained this fast; rc=%s)"
                          % proc.returncode)
        return case_fails, None
    if not os.path.isfile(journal):
        case_fails.append("no journal file while running")

    # 3) SIGTERM: exit within EXIT_BOUND.
    t0 = time.time()
    proc.send_signal(signal.SIGTERM)
    while time.time() - t0 < EXIT_BOUND:
        if proc.poll() is not None:
            break
        time.sleep(0.25)
    elapsed = time.time() - t0
    if proc.poll() is None:
        proc.kill()
        proc.wait()
        case_fails.append("daemon did not exit within %.0fs of SIGTERM "
                          "(still alive after %.0fs; shutdown path broken)"
                          % (EXIT_BOUND, elapsed))
        return case_fails, None
    if proc.returncode not in ACCEPTED_RC:
        case_fails.append("daemon exited with rc=%s (expected %s)"
                          % (proc.returncode, ACCEPTED_RC))

    # 4) The journal on disk must be the complete, strictly ordered
    #    transcript of the workload: exactly one line per event, in ordinal
    #    order, with every digest recomputable from the event alone.
    if not os.path.isfile(journal):
        case_fails.append("no journal file after exit")
        return case_fails, None
    with open(journal, "r", encoding="utf-8", errors="replace") as fh:
        got = [line.rstrip("\n") for line in fh if line.strip()]

    if len(got) != len(want):
        case_fails.append("journal has %d lines, expected one per event = %d"
                          % (len(got), len(want)))
    else:
        for i, (g, w) in enumerate(zip(got, want)):
            if g != w:
                case_fails.append("journal line %d is %r, expected %r" % (i, g, w))
                break
    if got and len(got) != len(want):
        case_fails.append("first line present: %r" % got[0])

    if case_fails:
        with open(logfile, "r", encoding="utf-8", errors="replace") as fh:
            tail = "".join(fh.readlines()[-8:])
        case_fails.append("daemon log tail: " + tail.strip().replace("\n", " | "))
    return case_fails, elapsed


# --------------------------------------------------------------------------
# 0) Fixture integrity (workloads must be byte-identical to the authored set).
# --------------------------------------------------------------------------
for path, want in FIXTURE_SHA256.items():
    if not os.path.isfile(path):
        fail("missing fixture " + path)
        continue
    if sha256(path) != want:
        fail("fixture mismatch %s: workload replaced or weakened" % path)

# --------------------------------------------------------------------------
# 1) Deliverables exist and the build contract executes.
# --------------------------------------------------------------------------
if not os.path.isfile(BUILD):
    fail("missing deliverable " + BUILD)
if not os.path.isfile(RUN):
    fail("missing deliverable " + RUN)

if not failures:
    build = subprocess.run(["bash", BUILD], capture_output=True, text=True)
    if build.returncode != 0:
        fail("build.sh failed: " + build.stderr.strip()[-400:])

if not failures:
    check = subprocess.run(["bash", CHECK], capture_output=True, text=True)
    if check.returncode != 0:
        fail("shipped semantic check suite no longer passes: "
             + (check.stdout + check.stderr).strip()[-400:])

# --------------------------------------------------------------------------
# 2) The lifecycle across the visible sample and the hidden workloads.
# --------------------------------------------------------------------------
cases = [("sample", SAMPLE)]
if os.path.isdir(HIDDEN):
    for name in sorted(os.listdir(HIDDEN)):
        case_dir = os.path.join(HIDDEN, name)
        if os.path.isdir(case_dir) and os.path.isfile(os.path.join(case_dir, "workload.txt")):
            cases.append((name, os.path.join(case_dir, "workload.txt")))
else:
    fail("no hidden cases mounted at " + HIDDEN)

if not failures:
    if len([c for c in cases if c[0] != "sample"]) < 2:
        fail("need at least 2 hidden generalization cases")

if not failures:
    for i, (name, wpath) in enumerate(cases):
        msg, elapsed = run_case(name, wpath, "/tmp/kcairn/%s" % name)
        if msg:
            for m in msg:
                fail("case %s: %s" % (name, m))
        else:
            print("case %-7s OK (%d events, exited in %.1fs, journal complete)" %
                  (name, len(parse_workload(wpath)), elapsed))

if failures:
    print("keelson-cairn FAILURES:")
    for m in failures:
        print("  - " + m)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
else:
    print("keelson-cairn ALL PASS")
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("1")
sys.exit(0)
PY