#!/bin/bash
# Verifier for jib-tarn (executes-deliverable).
#
# Checks, in order:
#   0. the deliverables exist (/app/repo, /app/bench.json)
#   1. /app/repo is a git working tree with the 25-commit history, including
#      the regression commit b1ba5ab7 as an ancestor of HEAD
#   2. the repository's own pytest suite (which contains the agent's new
#      benchmark regression test) is green, and at least as many tests pass
#      as the pristine fixture shipped
#   3. /app/bench.json matches the harness schema, and re-running the harness
#      on /app/repo shows sub-quadratic scaling
#   4. the hot path times at the three hidden input sizes stay within a
#      generous factor of the reference implementation (tests/ref)
#   5. re-introducing the regression (swapping in the fixture's original
#      hot-path module) makes at least one test file fail that passes on the
#      fixed repository -- i.e. the agent's benchmark test really catches the
#      regression
#
# Reward is binary: 1 only if every check passes.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
REPO = "/app/repo"
CULPRIT = "b1ba5ab7bc5f59250dbcf6bee124b5d6b98b0d2e"
DECL_PATH = "/tests/hidden/decl.json"
AGENT_TIME = "/tests/hidden/agent_time.py"
REF_TIME = "/tests/ref/ref_window.py"
BENCH_JSON = "/app/bench.json"

failures = []


def fail(msg):
    failures.append(msg)


def run(cmd, cwd=None, timeout=300):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT after %ss" % timeout


# ---------------------------------------------------------------------------
# 0) deliverables
# ---------------------------------------------------------------------------
if not os.path.isdir(REPO):
    fail("missing deliverable /app/repo; reward is 0")
if not os.path.isfile(BENCH_JSON):
    fail("missing deliverable /app/bench.json")

if not os.path.isdir(REPO):
    print("FAILURES")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

# ---------------------------------------------------------------------------
# 1) repository shape and history
# ---------------------------------------------------------------------------
rc, _, _ = run(["git", "-C", REPO, "rev-parse", "--is-inside-work-tree"])
if rc != 0:
    fail("repo is not a git working tree")
rc, out, _ = run(["git", "-C", REPO, "rev-list", "--count", "HEAD"])
if rc != 0:
    fail("cannot count commits")
else:
    try:
        ncommits = int(out.strip())
    except ValueError:
        ncommits = -1
    if ncommits < 25:
        fail("expected the 25-commit history (or more); got %s commits" % ncommits)
rc, _, _ = run(["git", "-C", REPO, "cat-file", "-e", CULPRIT + "^{commit}"])
if rc != 0:
    fail("regression commit %s is missing from history" % CULPRIT[:12])
else:
    rc, _, _ = run(["git", "-C", REPO, "merge-base", "--is-ancestor",
                    CULPRIT, "HEAD"])
    if rc != 0:
        fail("regression commit %s is not an ancestor of HEAD" % CULPRIT[:12])

# ---------------------------------------------------------------------------
# 2) the deliverable executes and its suite is green (this also runs the
#    agent's benchmark regression test)
# ---------------------------------------------------------------------------
rc, out, err = run(["python3", "-m", "pytest", "-q"], cwd=REPO, timeout=500)
if rc != 0:
    tail = (out or "")[-2000:] + (err or "")[-500:]
    fail("pytest suite failed (rc=%s): %s" % (rc, tail))
else:
    m = re.search(r"(\d+) passed", out or "")
    count = int(m.group(1)) if m else 0
    if count < 24:
        fail("suite collected only %s passing tests; the shipped fixture "
             "passes 24, so tests were removed or broken" % count)

# ---------------------------------------------------------------------------
# 3) bench.json contract and a fresh harness run
# ---------------------------------------------------------------------------
if os.path.isfile(BENCH_JSON):
    try:
        with open(BENCH_JSON) as fh:
            bj = json.load(fh)
    except Exception:
        bj = None
    ok = (isinstance(bj, dict) and bj.get("n") == [2000, 4000, 8000, 16000]
          and bj.get("k") == [1000, 2000, 4000, 8000]
          and isinstance(bj.get("ms"), list) and len(bj["ms"]) == 4)
    if not ok:
        fail("bench.json does not match {\"n\": [...4 sizes...], \"k\": [...], "
             "\"ms\": [...4 numbers...]}")
    else:
        ms = bj["ms"]
        if not all(isinstance(v, (int, float)) and v > 0 for v in ms):
            fail("bench.json ms entries must be positive numbers")
        elif ms[3] > 12.0 * ms[1]:
            fail("bench.json scaling looks quadratic: ms[3]=%.1f vs ms[1]=%.1f"
                 % (ms[3], ms[1]))
else:
    fail("/app/bench.json missing")

rc, out, err = run(["python3", "benchmarks/bench.py", "--repeats", "3",
                    "--json", "/tmp/recheck.json"], cwd=REPO, timeout=300)
if rc != 0:
    fail("harness re-run failed (rc=%s): %s" % (rc, (err or out)[-600:]))
else:
    try:
        with open("/tmp/recheck.json") as fh:
            rj = json.load(fh)
        ms = rj["ms"]
    except Exception:
        fail("harness re-run output unreadable")
        ms = None
    if ms is not None:
        if not all(isinstance(v, (int, float)) and v > 0 for v in ms):
            fail("harness re-run produced non-positive timings")
        elif ms[3] > 12.0 * ms[1]:
            fail("harness re-run scaling looks quadratic: ms[3]=%.1f ms, "
                 "ms[1]=%.1f ms" % (ms[3], ms[1]))

# ---------------------------------------------------------------------------
# 4) hidden input sizes against the reference implementation
# ---------------------------------------------------------------------------
try:
    with open(DECL_PATH) as fh:
        decl = json.load(fh)
    for s in decl["sizes"]:
        k = max(1, int(s * decl["k_ratio"]))
        seed = int.from_bytes(os.urandom(4), "big") & 0x7FFFFFFF
        rc_a, out_a, err_a = run(
            ["python3", AGENT_TIME, str(seed), str(s), str(k)], timeout=200)
        rc_r, out_r, _ = run(
            ["python3", REF_TIME, str(seed), str(s), str(k)], timeout=200)
        if rc_a != 0:
            fail("hidden size %d: agent hot path errored/timed out: %s"
                 % (s, (err_a or out_a)[-300:]))
            continue
        if rc_r != 0:
            fail("hidden size %d: reference driver failed" % s)
            continue
        try:
            ag = json.loads(out_a)
            rf = json.loads(out_r)
        except Exception:
            fail("hidden size %d: unparseable timing output" % s)
            continue
        limit = max(decl["floor_sec"],
                    min(rf["ms"] / 1000.0 * decl["factor"], decl["cap_sec"]))
        if ag["ms"] / 1000.0 > limit:
            fail("hidden size %d: agent %.1f ms exceeds the generous limit "
                 "%.1f ms (reference %.1f ms)" % (s, ag["ms"], limit * 1000.0,
                                                  rf["ms"]))
except OSError as e:
    fail("cannot read hidden declaration: %s" % e)

# ---------------------------------------------------------------------------
# 5) benchmark test must fail against a re-introduced regression
# ---------------------------------------------------------------------------
work = "/tmp/jib-swap"
shutil.rmtree(work, ignore_errors=True)
fixed_dir = os.path.join(work, "fixed")
reg_dir = os.path.join(work, "regressed")
shutil.copytree(REPO, fixed_dir)
shutil.copytree(REPO, reg_dir)
# Re-introduce the regression exactly as the fixture shipped it.
shutil.copy("/tests/hidden/buggy/window.py",
            os.path.join(reg_dir, "src", "sundial", "window.py"))

fixed_bad = set()
reg_bad = set()
tests_dir = os.path.join(REPO, "tests")
test_files = sorted(
    os.path.relpath(os.path.join(dp, fn), tests_dir)
    for dp, _, fns in os.walk(tests_dir)
    for fn in fns
    if fn.endswith(".py") and fn.startswith("test_")
)
for tf in test_files:
    args = ["python3", "-m", "pytest", "-q", "--no-header",
            "-p", "no:cacheprovider", os.path.join("tests", tf)]
    rc_f, _, _ = run(args, cwd=fixed_dir, timeout=200)
    if rc_f not in (0, 5):  # 5 == nothing collected, treat as green
        fixed_bad.add(tf)
    rc_r, _, _ = run(args, cwd=reg_dir, timeout=200)
    if rc_r not in (0, 5):
        reg_bad.add(tf)
if fixed_bad:
    fail("test file(s) FAIL on the fixed repository: %s" % sorted(fixed_bad))
reg_diff = reg_bad - fixed_bad
if not reg_diff:
    fail("re-introducing the regression made no test file fail: no benchmark "
         "test is protecting the suite")
else:
    # The failing-on-regressed file must actually be a timing test of the hot
    # path, otherwise any assertion that happens to flip between the module
    # versions (docstring, import list, ...) would satisfy the check.
    def is_timing_test(rel):
        try:
            with open(os.path.join(tests_dir, rel), encoding="utf-8",
                      errors="replace") as fh:
                src = fh.read()
        except OSError:
            return False
        return bool(re.search(r"perf_counter|process_time|timeit",
                              src)
                    and re.search(r"\bslide\b", src))

    if not any(is_timing_test(tf) for tf in reg_diff):
        fail("test file(s) fail on the regressed copy but are not timing "
             "tests of the hot path: %s" % sorted(reg_diff))

# ---------------------------------------------------------------------------
# reward
# ---------------------------------------------------------------------------
if failures:
    print("FAILURES (%d):" % len(failures))
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS: repo history, green suite (%d tests), bench.json, hidden-size "
      "timings vs reference, regression-sensitive benchmark test" % count)
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY