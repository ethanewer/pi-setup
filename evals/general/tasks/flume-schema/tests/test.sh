#!/bin/bash
# Verifier for flume-schema (executes-deliverable).
#
# Executes /app/agent_loop.py on the visible transcript and on every hidden
# transcript, and asserts that each run log matches the expected run EXACTLY:
# the tool-call sequence (tool, arguments, outcome, retries per step), the
# error messages fed back to the model, the final answer / termination reason
# (completed vs step_cap), and the deterministic final tool-store state.
# A strict 120s per-run timeout proves the step cap is enforced.
#
# Writes /logs/verifier/reward.txt (1 = all pass, 0 = any fail) on EVERY exit
# path (EXIT trap).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json
import os
import subprocess
import sys

LOOP = "/app/agent_loop.py"
RUN_A = "/app/run_A.json"
EXP_VISIBLE = "/tests/expected_A.json"
VISIBLE_TRANSCRIPT = "/app/transcripts/session_A.json"
HIDDEN_DIR = "/tests/hidden"

failures = []


def fail(msg):
    failures.append(msg)


def deep_equal(a, b, path="$"):
    """Exact recursive comparison.  Floats must be bit-identical: every value
    in this task is an exact decimal (quarters/halves), so tolerance-free
    equality is the contract."""
    if type(a) is not type(b):
        return "type %s vs %s at %s" % (type(a).__name__, type(b).__name__, path)
    if isinstance(a, dict):
        if set(a.keys()) != set(b.keys()):
            return "key set %s vs %s at %s" % (sorted(a), sorted(b), path)
        for k in a:
            r = deep_equal(a[k], b[k], "%s.%s" % (path, k))
            if r:
                return r
        return None
    if isinstance(a, list):
        if len(a) != len(b):
            return "length %d vs %d at %s" % (len(a), len(b), path)
        for i, (x, y) in enumerate(zip(a, b)):
            r = deep_equal(x, y, "%s[%d]" % (path, i))
            if r:
                return r
        return None
    if isinstance(a, float):
        if a != b:
            return "float %r vs %r at %s" % (a, b, path)
        return None
    if a != b:
        return "%r vs %r at %s" % (a, b, path)
    return None


def run_loop(tag, transcript, out):
    try:
        r = subprocess.run([sys.executable, LOOP, transcript, out],
                           capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        fail("%s: run did not terminate within 120 s -- step cap not enforced?" % tag)
        return None
    if r.returncode != 0:
        fail("%s: loop exited %d: %s" % (tag, r.returncode,
                                         (r.stderr or r.stdout).strip()[:400]))
        return None
    try:
        return json.load(open(out))
    except Exception as exc:
        fail("%s: run log is not JSON: %s" % (tag, exc))
        return None


def check_run(tag, transcript, expected):
    out = "/tmp/flume_%s_out.json" % tag
    if os.path.exists(out):
        os.remove(out)
    got = run_loop(tag, transcript, out)
    if got is None:
        return
    d = deep_equal(got, expected)
    if d:
        fail("%s: log mismatch -- %s" % (tag, d))
        return
    # structural sanity independent of the stored expectation
    steps = got.get("steps")
    if not isinstance(steps, list) or not steps:
        fail("%s: no steps recorded" % tag)
    for s in steps:
        if s.get("outcome") not in ("executed", "replayed", "malformed",
                                    "schema_error", "unknown_tool", "error",
                                    "final"):
            fail("%s: step %s has unknown outcome %r" % (tag, s.get("step"),
                                                         s.get("outcome")))
            break
        if s.get("outcome") == "executed" and not isinstance(s.get("result"), dict):
            fail("%s: executed step %s has no result" % (tag, s.get("step")))
            break


if not os.path.exists(LOOP):
    fail("missing deliverable /app/agent_loop.py")
else:
    src = open(LOOP).read()
    if "/tests" in src:
        fail("/app/agent_loop.py references /tests (forbidden)")

    # 1) the agent's own visible run artifact must match the expected run
    if not os.path.exists(RUN_A):
        fail("missing deliverable /app/run_A.json")
    else:
        try:
            run_a = json.load(open(RUN_A))
        except Exception as exc:
            fail("deliverable /app/run_A.json does not parse: %s" % exc)
            run_a = None
        if run_a is not None:
            d = deep_equal(run_a, json.load(open(EXP_VISIBLE)))
            if d:
                fail("visible /app/run_A.json mismatch -- %s" % d)

    # 2. fresh rerun of the loop on the visible transcript
    exp_visible = json.load(open(EXP_VISIBLE))
    check_run("A", VISIBLE_TRANSCRIPT, exp_visible)

    # 3. hidden generalization cases
    cases = sorted(n for n in os.listdir(HIDDEN_DIR)
                   if os.path.isdir(os.path.join(HIDDEN_DIR, n)))
    if len(cases) < 2:
        fail("expected at least 2 hidden cases, found %d" % len(cases))
    for case in cases:
        tpath = os.path.join(HIDDEN_DIR, case, "transcript.json")
        epath = os.path.join(HIDDEN_DIR, case, "expected.json")
        if not (os.path.exists(tpath) and os.path.exists(epath)):
            fail("%s: missing transcript.json or expected.json" % case)
            continue
        check_run(case, tpath, json.load(open(epath)))

if failures:
    print("flume-schema verifier FAILURES:")
    for m in failures:
        print("  - " + m)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
    sys.exit(0)

print("ALL PASS: visible + %d hidden transcripts reproduced exactly" % len(cases))
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1")
sys.exit(0)
PY