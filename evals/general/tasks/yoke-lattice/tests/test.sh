#!/usr/bin/env bash
# Verifier for yoke-lattice (executes-deliverable).
#
# Executes the delivered local runner on the agent's own workflow AND on three
# hidden workflow fixtures, asserting:
#   1. the workflow itself is a valid 3+ job graph within the documented
#      subset (static check),
#   2. the runner's job order is a valid topological order of the graph,
#   3. a job whose `needs:` failed is skipped (hidden fixtures),
#   4. `if:` conditions (job- and step-level) were evaluated (hidden fixtures),
#   5. the machine-readable summary JSON matches the expectation exactly,
#   6. per-job artifacts were genuinely written by the executed steps.
# Writes exactly 1 or 0 to /logs/verifier/reward.txt.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json
import os
import shutil
import subprocess
import sys

import yaml

RUNNER = "/app/run_pipeline.sh"
WORKFLOW = "/app/.github/workflows/ci.yml"
HIDDEN = "/tests/hidden"
ALLOWED_JOB = {"name", "needs", "if", "outputs", "steps", "runs-on",
               "timeout-minutes", "permissions", "concurrency", "strategy",
               "env", "container"}
ALLOWED_STEP = {"id", "name", "if", "run", "env"}
failures = []
jobs = None


def fail(msg):
    failures.append(msg)


def check(cond, msg):
    if not cond:
        fail(msg)


def read_json(p):
    with open(p) as fh:
        return json.load(fh)


def wf_needs_for(jid):
    needs = (jobs or {}).get(jid, {}).get("needs", [])
    if isinstance(needs, str):
        needs = [needs]
    return needs


def diff(a, b, path):
    """Return a list of human-readable mismatches between a and b."""
    out = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a:
                out.append("%s: expected key %r missing" % (path, k))
            elif k not in b:
                out.append("%s: unexpected key %r" % (path, k))
            else:
                out.extend(diff(a[k], b[k], "%s.%s" % (path, k)))
        return out
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append("%s: list length %d != %d" % (path, len(a), len(b)))
        for i, (x, y) in enumerate(zip(a, b)):
            out.extend(diff(x, y, "%s[%d]" % (path, i)))
        return out
    if type(a) is not type(b) or a != b:
        out.append("%s: %r != %r" % (path, a, b))
    return out


def run_runner(workflow, rundir, workspace=None):
    args = ["bash", RUNNER, workflow, rundir]
    if workspace is not None:
        args += ["--workspace", workspace]
    r = subprocess.run(args, capture_output=True, text=True)
    return r


# =====================================================================
# 1) static contract checks on the delivered workflow
# =====================================================================
check(os.path.isfile(RUNNER), "deliverable %s is missing" % RUNNER)
check(os.access(RUNNER, os.X_OK), "deliverable %s is not executable" % RUNNER)
if not os.path.isfile(WORKFLOW):
    fail("deliverable %s is missing" % WORKFLOW)
else:
    try:
        with open(WORKFLOW) as fh:
            wf = yaml.safe_load(fh)
    except yaml.YAMLError as e:
        fail("delivered workflow is not valid YAML: %s" % e)
        wf = None
    if wf is not None:
        jobs = wf.get("jobs")
        check(isinstance(jobs, dict), "workflow has no jobs mapping")
        if isinstance(jobs, dict):
            check(len(jobs) >= 3, "workflow must declare at least 3 jobs")
            some_needs = False
            for jid, spec in jobs.items():
                check(isinstance(spec, dict), "job %r is not a mapping" % jid)
                if not isinstance(spec, dict):
                    continue
                for k in spec:
                    check(k in ALLOWED_JOB,
                          "job %r uses unsupported key %r" % (jid, k))
                check("steps" in spec, "job %r has no steps" % jid)
                steps = spec.get("steps")
                check(isinstance(steps, list) and len(steps) >= 1,
                      "job %r steps must be a non-empty list" % jid)
                if isinstance(steps, list):
                    for i, st in enumerate(steps, 1):
                        check(isinstance(st, dict),
                              "job %r step %d is not a mapping" % (jid, i))
                        if not isinstance(st, dict):
                            continue
                        for k in st:
                            check(k in ALLOWED_STEP,
                                  "job %r step %d uses unsupported key %r"
                                  % (jid, i, k))
                        check(isinstance(st.get("run"), str) and st["run"],
                              "job %r step %d needs a non-empty run" % (jid, i))
                needs = spec.get("needs", [])
                if isinstance(needs, str):
                    needs = [needs]
                if needs:
                    some_needs = True
                    for n in needs:
                        check(n in jobs,
                              "job %r needs unknown job %r" % (jid, n))
            check(some_needs, "no job declares a dependency graph (needs)")

# =====================================================================
# 2) run the runner on the agent's own workflow
# =====================================================================
vis = os.path.join("/tmp", "yoke-vis")
shutil.rmtree(vis, ignore_errors=True)
os.makedirs(vis)
r = run_runner(WORKFLOW, os.path.join(vis, "rundir"), workspace="/app")
check(r.returncode == 0,
      "runner failed on the delivered workflow: " + r.stderr.strip()[:300])
exp_vis = None
if r.returncode == 0 and os.path.isfile(os.path.join(vis, "rundir", "summary.json")):
    s = read_json(os.path.join(vis, "rundir", "summary.json"))
    check(s.get("workflow") == "ci.yml",
          "summary.workflow = %r, want 'ci.yml'" % s.get("workflow"))
    order = s.get("order")
    sjobs = s.get("jobs")
    check(isinstance(order, list) and isinstance(sjobs, dict),
          "summary is missing order/jobs")
    if isinstance(order, list) and isinstance(sjobs, dict):
        check(sorted(order) == sorted(jobs or {}),
              "summary order lists jobs different from the workflow: %s"
              % order)
        pos = {j: i for i, j in enumerate(order)}
        # topological validity: every need precedes its dependent
        for jid in order:
            needs = (jobs or {}).get(jid, {}).get("needs", [])
            if isinstance(needs, str):
                needs = [needs]
            for n in needs:
                check(pos.get(n, -1) < pos.get(jid, -1),
                      "job %r runs before its need %r violates topo order"
                      % (jid, n))
        # status/skip consistency
        any_ran = False
        for jid, j in sjobs.items():
            st = j.get("status")
            check(st in ("success", "failure", "skipped"),
                  "job %r: bad status %r" % (jid, st))
            reason = j.get("skip_reason")
            check(reason in (None, "needs", "if"),
                  "job %r: bad skip_reason %r" % (jid, reason))
            check(j.get("needs", []) == wf_needs_for(jid),
                  "job %r summary needs do not match the workflow" % jid)
            if st == "skipped":
                deps = j.get("needs", [])
                deps_failed = any(
                    sjobs[d]["status"] in ("failure", "skipped") for d in deps)
                check((reason == "needs") == deps_failed,
                      "job %r skipped with reason %r but needs %s"
                      % (jid, reason, deps))
                check(j.get("steps") == [], "skipped job %r has steps" % jid)
                check(j.get("outputs") == {}, "skipped job %r has outputs" % jid)
            else:
                any_ran = any_ran or any(
                    x.get("status") in ("success", "failure")
                    for x in j.get("steps", []))
                steps = j.get("steps", [])
                for i, x in enumerate(steps, 1):
                    check(x.get("index") == i,
                          "job %r step order broken at %r" % (jid, x))
                    check(x.get("status") in ("success", "failure", "skipped"),
                          "job %r step %d: bad status %r" % (jid, i,
                                                              x.get("status")))
                    if x.get("status") == "skipped":
                        check(x.get("exit_code") is None,
                              "job %r step %d: skipped step has exit_code"
                              % (jid, i))
                    else:
                        check(isinstance(x.get("exit_code"), int),
                              "job %r step %d: exit_code %r not an int"
                              % (jid, i, x.get("exit_code")))
                    check(x.get("id") is None or isinstance(x.get("id"), str),
                          "job %r step %d: bad id" % (jid, i))
                    check(x.get("name") is None
                          or isinstance(x.get("name"), str),
                          "job %r step %d: bad name" % (jid, i))
                check(isinstance(j.get("outputs"), dict),
                      "job %r outputs not a dict" % jid)
            # artifact dir for jobs that executed steps
            if any(x.get("status") in ("success", "failure")
                   for x in j.get("steps", [])):
                check(os.path.isdir(os.path.join(vis, "rundir", "jobs", jid)),
                      "no artifact dir for executed job %r" % jid)
        check(any_ran, "no job executed any step (pipeline did nothing)")

# =====================================================================
# 3) hidden fixtures: exact summary match + real artifact execution
# =====================================================================
cases = sorted(n for n in os.listdir(HIDDEN)
               if os.path.isdir(os.path.join(HIDDEN, n)))
check(len(cases) >= 2, "expected >=2 hidden cases")

ARTIFACT_CHECKS = {
    "H1": {
        "rundir/jobs/compile/here.txt": b"local\n",
        "rundir/jobs/check/checked.txt": b"tiles\n",
        "rundir/jobs/ship/bundle.txt": b"tiles\ntiles\n",
        "rundir/jobs/monitor/page.txt": b"paged\n",
        "rundir/jobs/release-notes": None,
        "rundir/jobs/postclean": None,
        "out/tile.txt": b"tiles\n",
    },
    "H2": {
        "rundir/jobs/build/version.txt": b"0.4.0",
        "rundir/jobs/build/always.txt": b"touched\n",
        "rundir/jobs/test/test-ok.txt": b"yes\n",
        "rundir/jobs/package/shipped.txt": b"shipped\n",
        "rundir/jobs/deploy/event.txt": b"push\n",
        "rundir/jobs/deploy/deployed.txt": b"deployed\n",
        "rundir/jobs/audit": None,
    },
    "H3": {
        "rundir/jobs/beta/mode.txt": b"strict\n",
        "rundir/jobs/beta/name.txt": b"beta\n",
        "rundir/jobs/alpha/name.txt": b"alpha\n",
        "rundir/jobs/delta/joined.txt": b"beta\n",
        "rundir/jobs/gamma/joined.txt": b"alpha\n",
        "rundir/jobs/hub/merged.txt": b"MERGE-POINT",
        "rundir/jobs/hub/size.txt": b"11\n",
        "rundir/jobs/fin/who.txt": b"fin\n",
        "beta-name.txt": b"beta\n",
        "alpha-name.txt": b"alpha\n",
        "hub-merged.txt": b"MERGE-POINT",
    },
}

root = "/tmp/yoke-hid"
shutil.rmtree(root, ignore_errors=True)
os.makedirs(root)
for case in cases:
    if case not in ARTIFACT_CHECKS:
        fail("no artifact expectations for hidden case %r" % case)
        continue
    expect_path = os.path.join(HIDDEN, case, "expected.json")
    work = os.path.join(root, case)
    shutil.copytree(os.path.join(HIDDEN, case), work)
    rundir = os.path.join(work, "rundir")
    r = run_runner(os.path.join(work, "workflow.yml"), rundir)
    check(r.returncode == 0,
          "%s: runner failed: %s" % (case, r.stderr.strip()[:300]))
    if r.returncode != 0:
        continue
    got = read_json(os.path.join(rundir, "summary.json"))
    want = read_json(expect_path)
    mism = diff(got, want, case)
    for m in mism:
        fail("summary mismatch: " + m)
    # artifact presence + byte content (execution proof)
    for rel, wantb in ARTIFACT_CHECKS[case].items():
        p = os.path.join(work, rel)
        if wantb is None:
            check(not os.path.exists(p),
                  "%s: %s should not exist but does" % (case, rel))
        else:
            check(os.path.isfile(p), "%s: artifact %s missing" % (case, rel))
            if os.path.isfile(p):
                with open(p, "rb") as fh:
                    gotb = fh.read()
                check(gotb == wantb,
                      "%s: artifact %s content %r != %r"
                      % (case, rel, gotb, wantb))

if failures:
    print("FAILURES (%d):" % len(failures))
    for m in failures:
        print("  - " + m)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
    sys.exit(0)

print("ALL PASS: visible consistency + %d hidden cases exact-match" % len(cases))
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1")
sys.exit(0)
PY