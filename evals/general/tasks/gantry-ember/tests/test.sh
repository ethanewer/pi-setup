#!/bin/bash
# gantry-ember verifier (executes-deliverable).
#
# The agent must make the /app/dutywheel suite pass deterministically.
# This verifier:
#   1. byte-checks every shipped test file (the tests are frozen: the agent
#      must fix behavior, not the tests);
#   2. runs the full suite 20 times, each at a pinned PYTHONHASHSEED, and
#      requires every run green (all tests pass, none skipped/failed);
#   3. runs it 20 more times at a second set of distinct seeds, again all
#      green.  The pinned seeds are picked to reproduce the shipped
#      nondeterminism deterministically: each one triggers the pre-fix
#      flaky test, so an untouched container never passes, while a fixed
#      deliverable is green under every seed;
#   4. overlays two hidden source mutations (a stuck wheel, a truncated
#      roster) and requires the suite to FAIL under each, proving the
#      tests still detect real regressions;
#   5. runs a seed-independent contract probe (tests/contract_probe.py)
#      directly against the delivered wheel: the same roster snapshot must
#      pick the same member in every process (different hash seeds), and
#      the member who carried the previous cycle must never be re-picked
#      while anyone else is available.  The probe builds its own roster and
#      exercises only the public API, so the seed list above is a
#      convenience for the negative control, not the whole of it: even if
#      interpreter hash behavior ever shifted and no pinned seed tripped
#      the pre-fix bug, this probe still rejects the untouched tree.
# Reward is exactly "1" or "0".
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import os
import re
import shutil
import subprocess
import sys

REPO = "/app/dutywheel"
SUITE_DIR = "tests"
MIN_TESTS = 16                    # shipped suite has 16 tests; none may vanish
MUTANT_SEED = "7"

# sha256 of the shipped, frozen test files.  Any edit to a test (deleting,
# skipping, weakening, adding bypasses) changes one of these.
TEST_HASHES = {
    "conftest.py":       "a12cd2dddf563d2fd4d44dd6a17ee0dcede85f2d14e41c94b6371d43bb0411d7",
    "test_crew.py":      "6c27d179d578c6e6b411592be8f8a93bc777da89d695ffb246be7297e747ce31",
    "test_rotation.py":  "eee63e2d0bb4fa1e1510c42f993b9390142d9b7e74fc06087ae259663eadef4d",
    "test_schedule.py":  "ce0a383491922a7e09fccf9289c71156b0bfbf51aef13e50f605c1d9751c70da",
}

# 40 seeds pinned for reproduce-on-demand: every one of them deterministically
# trips the shipped flaky test, so the untouched container scores 0 here.
SEEDS_PHASE_A = [143183475, 144477015, 152071650, 183743730, 223010445,
                 239493255, 318026685, 334509495, 421931100, 524541975,
                 587886135, 636041025, 771617520, 779212155, 818478870,
                 826073505, 833668140, 1040183430, 1049071605, 1246698720]
SEEDS_PHASE_B = [1460808645, 1486179630, 1629350760, 1715478825, 1882727400,
                 1905511305, 1994226450, 2024604990, 2169069660, 2200741740,
                 2351507505, 2438929110, 2597289510, 2612478780, 2645444400,
                 2731572465, 2739167100, 2748055275, 2770839180, 2787321990]

failures = []


def fail(msg):
    failures.append(msg)


def sha256(path):
    import hashlib
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def run_suite(workdir, seed, label):
    """Run the dutywheel suite; returns (rc, summary_line, output)."""
    env = dict(os.environ)
    env["PYTHONHASHSEED"] = str(seed)
    proc = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", SUITE_DIR],
        cwd=workdir, env=env, capture_output=True, text=True, timeout=120)
    out = proc.stdout + proc.stderr
    line = ""
    for ln in reversed(out.splitlines()):
        if "passed" in ln or "failed" in ln:
            line = ln.strip()
            break
    return proc.returncode, line, out


def check_green(workdir, seed, label):
    rc, line, out = run_suite(workdir, seed, label)
    problems = []
    if rc != 0:
        problems.append("pytest exit code %d" % rc)
    low = out.lower()
    for token in ("failed", "skipped", "error", "xfailed", "deselected"):
        if re.search(r"\b%s\b" % token, low):
            problems.append("output mentions %r" % token)
    m = re.search(r"(\d+)\s+passed", low)
    if not m:
        problems.append("no passed-count found")
    elif int(m.group(1)) < MIN_TESTS:
        problems.append("only %s tests passed (expected >= %d)"
                        % (m.group(1), MIN_TESTS))
    if problems:
        fail("%s: suite NOT green: %s | summary: %r"
             % (label, "; ".join(problems), (line or out[-200:])))
        return False
    return True


# ---- 0) deliverable present --------------------------------------------
if not os.path.isdir(REPO):
    fail("deliverable /app/dutywheel missing")
else:
    # ---- 1) shipped test files frozen ----------------------------------
    for name, want in TEST_HASHES.items():
        path = os.path.join(REPO, SUITE_DIR, name)
        if not os.path.isfile(path):
            fail("test file missing: %s" % path)
        elif sha256(path) != want:
            fail("test file modified: %s (tests are frozen; fix the code, "
                 "not the test)" % name)

    # ---- 2)+3) 40 full-suite runs, all green ---------------------------
    for phase, seeds in (("A", SEEDS_PHASE_A), ("B", SEEDS_PHASE_B)):
        for i, seed in enumerate(seeds):
            check_green(REPO, seed,
                        "phase %s run %d/%d (seed %d)" % (phase, i + 1, len(seeds), seed))

    # ---- 4) hidden source mutants must make the suite fail -------------
    mutants = [
        ("mutant_wheel_never_advances", "dutywheel/rotation.py"),
        ("mutant_short_roster", "dutywheel/crew.py"),
    ]
    hidden = "/tests/hidden"
    for case, rel in mutants:
        src = os.path.join(hidden, case, os.path.basename(rel))
        work = "/tmp/mut_%s" % case
        shutil.rmtree(work, ignore_errors=True)
        shutil.copytree(REPO, work)
        if not os.path.isfile(src):
            fail("hidden mutant fixture missing: %s" % src)
            continue
        shutil.copyfile(src, os.path.join(work, rel))
        rc, line, out = run_suite(work, MUTANT_SEED, "mutant %s" % case)
        if rc == 0 and not re.search(r"^FAILED", out, re.M):
            fail("mutant %s survived: the suite stayed green after the "
                 "mutation (%r)" % (case, (line or out[-200:])))
        else:
            # expected: at least one test goes red
            m = re.search(r"(\d+)\s+failed", out.lower())
            print("    mutant %s -> suite fails (exit %d%s)"
                  % (case, rc, ", %s failed" % m.group(1) if m else ""))

    # ---- 5) seed-independent contract probe ---------------------------
    probe = "/tests/contract_probe.py"
    if not os.path.isfile(probe):
        fail("contract probe script missing: %s" % probe)
    else:
        proc = subprocess.run([sys.executable, probe],
                              capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            fail("contract probe rejected the deliverable (exit %d)"
                 % proc.returncode)
            body = (proc.stdout or "") + (proc.stderr or "")
            if body.strip():
                print("    " + body.strip().replace("\n", "\n    "))
        else:
            print("    contract probe -> %s" % proc.stdout.strip())

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS: 40/40 full-suite runs green under pinned seeds; "
      "every shipped test intact; both hidden mutants caught; "
      "contract probe green")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY