#!/bin/bash
# Verifier for cistern-sound (executes-deliverable).
#
# Grading model: the specification is internally contradictory (README R4 vs
# R7). Two coherent resolutions exist (every group at its gross total, or
# every group at its settled/net total). The verifier
#   (1) executes the deliverable CLI (/app/paygate/cli.py via `python3 -m
#       paygate`) on the shipped ledger and on every hidden ledger,
#   (2) asserts every displayed total is exactly one of the two candidate
#       values (gross, net) for its group - any third value, extra/missing
#       group, or renamed/relabelled group is a fail,
#   (3) asserts the resolution is the SAME across the visible and all hidden
#       ledgers - a mixed rule (or a name heuristic) fails,
#   (4) asserts /app/decisions.md quotes both conflicting requirements,
#   (5) asserts the shipped README was not vandalised (both phrases intact)
#       and the visible ledger was not edited,
#   (6) re-runs the repository test suite and requires it green.
# Reward is binary and every path writes it.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import hashlib
import json
import os
import subprocess
import sys

R4 = "no netting, deduction, or adjustment applied"
R7 = "a gross figure for such a group is misleading"
VIS_LEDGER = "/app/ledger.json"
VIS_SHA = "73fd534839d44b543a79cafc62235e38e42e75fc1b0893127a62eab8604c540d"

failures = []


def fail(msg):
    failures.append(msg)


def run_cli(ledger_path, out_path):
    return subprocess.run(
        [sys.executable, "-m", "paygate", ledger_path, out_path],
        capture_output=True, text=True, cwd="/app")


def group_candidates(ledger):
    """id -> (gross, net, name, count) for every group in the fixture."""
    out = {}
    for g in ledger["groups"]:
        gross = sum(e["amount_cents"] for e in g["entries"])
        adj = sum(
            e.get("refund_cents", 0) + e.get("chargeback_cents", 0)
            for e in g["entries"])
        out[g["id"]] = (gross, gross - adj, g["name"], len(g["entries"]))
    return out


def assess(out, ledger):
    """Return ('G'|'N'|'BAD', messages)."""
    msgs = []
    cands = group_candidates(ledger)
    if out.get("period") != ledger["period"]:
        msgs.append("period %r != %r" % (out.get("period"), ledger["period"]))
    got = out.get("groups", {})
    if set(got) != set(cands):
        msgs.append("group ids %s != %s" % (sorted(got), sorted(cands)))
    ok_gross = True
    ok_net = True
    for gid, (gross, net, name, count) in cands.items():
        obj = got.get(gid)
        if obj is None:
            continue
        if set(obj) != {"name", "count", "total_cents"}:
            msgs.append("%s: object keys %s != {name, count, total_cents}"
                        % (gid, sorted(obj)))
            continue
        if obj["name"] != name:
            msgs.append("%s: name %r != %r" % (gid, obj["name"], name))
        if obj["count"] != count:
            msgs.append("%s: count %r != %r" % (gid, obj["count"], count))
        t = obj["total_cents"]
        if t not in (gross, net):
            msgs.append("%s: total %r is neither gross %r nor net %r "
                        "(third behaviour)" % (gid, t, gross, net))
        if t != gross:
            ok_gross = False
        if t != net:
            ok_net = False
    if "grand_total_cents" in out:
        try:
            s = sum(v["total_cents"] for v in got.values())
        except (TypeError, KeyError):
            s = None
        if s is not None and s != out.get("grand_total_cents"):
            msgs.append("grand_total_cents %r != sum of displayed %r"
                        % (out.get("grand_total_cents"), s))
    if msgs:
        return ("BAD", msgs)
    if ok_gross:
        return ("G", msgs)
    if ok_net:
        return ("N", msgs)
    msgs.append("some groups gross, some net - a mixed rule, not a resolution")
    return ("BAD", msgs)


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


# ---- 0) deliverable exists ----
if not os.path.isfile("/app/paygate/cli.py"):
    fail("deliverable /app/paygate/cli.py missing")

# ---- 1) decision record quotes both conflicting requirements ----
if not os.path.isfile("/app/decisions.md"):
    fail("deliverable /app/decisions.md missing")
else:
    dtext = open("/app/decisions.md", encoding="utf-8").read()
    if R4 not in dtext:
        fail("decisions.md does not quote R4 verbatim (missing %r)" % R4)
    if R7 not in dtext:
        fail("decisions.md does not quote R7 verbatim (missing %r)" % R7)

# ---- 2) the shipped spec is intact ----
rmd = open("/app/README.md", encoding="utf-8").read()
if R4 not in rmd:
    fail("README no longer contains the R4 phrase (spec vandalised)")
if R7 not in rmd:
    fail("README no longer contains the R7 phrase (spec vandalised)")

# ---- 3) the visible ledger is unmodified ----
vb = open(VIS_LEDGER, "rb").read()
if hashlib.sha256(vb).hexdigest() != VIS_SHA:
    fail("the shipped /app/ledger.json was modified (it is read-only input)")
    vis_ledger = None
else:
    vis_ledger = load(VIS_LEDGER)

# ---- 4) execute the deliverable on the visible fixture ----
classes = {}
if vis_ledger is not None:
    r = run_cli(VIS_LEDGER, "/tmp/cistern_vis.json")
    if r.returncode != 0:
        fail("visible run failed (%d): %s" % (r.returncode, r.stderr.strip()))
    else:
        cls, msgs = assess(load("/tmp/cistern_vis.json"), vis_ledger)
        for m in msgs:
            fail("visible: " + m)
        classes["visible"] = cls

# ---- 5) execute the deliverable on the hidden fixtures ----
hroot = "/tests/hidden"
hidden_cases = sorted(
    n for n in os.listdir(hroot)
    if os.path.isdir(os.path.join(hroot, n)))
if len(hidden_cases) < 3:
    fail("expected at least 3 hidden cases, found %d" % len(hidden_cases))
for case in hidden_cases:
    ledger_path = os.path.join(hroot, case, "ledger.json")
    if not os.path.isfile(ledger_path):
        fail("%s: no ledger.json" % case)
        continue
    ledger = load(ledger_path)
    out_path = "/tmp/cistern_%s.json" % case
    r = run_cli(ledger_path, out_path)
    if r.returncode != 0:
        fail("%s: CLI exited %d: %s" % (case, r.returncode, r.stderr.strip()))
        classes[case] = "BAD"
        continue
    cls, msgs = assess(load(out_path), ledger)
    for m in msgs:
        fail("%s: " % case + m)
    classes[case] = cls

# ---- 6) one coherent resolution across every fixture ----
if classes:
    vals = list(classes.values())
    if any(v not in ("G", "N") for v in vals):
        fail("no coherent resolution on every fixture: %s" % classes)
    elif len(set(vals)) != 1:
        fail("resolution differs across fixtures: %s" % classes)

# ---- 7) the repository test suite is green, and still exists ----
# The instruction forbids deleting tests; a suite reduced to one trivial
# test would otherwise "stay green" vacuously and the pinning-tests part of
# the task would be unmeasured. Guard the shipped suite file and a minimum
# number of test functions before running it.
tfile = "/app/paygate/tests/test_report.py"
if not os.path.isfile(tfile):
    fail("test suite missing: %s (the instruction forbids deleting tests)" % tfile)
else:
    ttext = open(tfile, encoding="utf-8").read()
    if ttext.count("def test_") < 3:
        fail("test suite gutted: expected >= 3 test functions in %s, "
             "found %d (do not delete tests)" % (tfile, ttext.count("def test_")))
r = subprocess.run([sys.executable, "-m", "pytest", "paygate/tests", "-q"],
                   capture_output=True, text=True, cwd="/app")
if r.returncode != 0:
    fail("paygate test suite not green (rc=%d): %s"
         % (r.returncode, r.stdout.strip()[-1200:]))

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS (resolution classes: %s)" % classes)
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY