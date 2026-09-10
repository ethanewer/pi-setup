#!/bin/bash
# Verifier for gantry-ledger (executes-deliverable).
#
# Executes /app/harness.py on the shipped prompts plus the agent's v3
# against the visible set and against three hidden record sets, independently
# re-scores the same model to prove the harness is genuinely wired to it, and
# asserts that (a) the documented v1/v2 trade-off is reproduced everywhere,
# (b) /app/prompts/v3.txt clears the declared bar on BOTH metrics with the
# declared tolerance, (c) /app/eval_report.json is a truthful record of the
# visible-set measurements, and (d) the harness survives a gold-mutated
# synthetic set whose true numbers differ sharply from the documented
# baseline, so a harness printing canned/documented numbers for the shipped
# prompts (or ignoring its records argument) fails the independent cross-check.
#
# Reward is written exactly once as "1" or "0".
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

if [ ! -f /app/harness.py ]; then
  echo "missing deliverable /app/harness.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -f /app/prompts/v3.txt ]; then
  echo "missing deliverable /app/prompts/v3.txt" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -f /app/eval_report.json ]; then
  echo "missing deliverable /app/eval_report.json" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json
import os
import subprocess
import sys

sys.path.insert(0, "/app")
import model

HARNESS = "/app/harness.py"
V1 = "/app/prompts/v1.txt"
V2 = "/app/prompts/v2.txt"
V3 = "/app/prompts/v3.txt"
VIS = "/app/data/records.jsonl"

# Documented baseline (reproduced by generation; see task docs).
DOC_V1_REF, DOC_V1_FAB = 0.60, 0.00
DOC_V2_REF, DOC_V2_FAB = 0.97, 0.19

failures = []


def fail(msg):
    failures.append(msg)


def load_records(path):
    recs = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                recs.append(json.loads(line))
    return recs


def reference_run(prompt_text, recs):
    """Independent scoring of the same deterministic model."""
    good = fab = 0
    for r in recs:
        out = model.extract(prompt_text, r["text"])
        if out.get("ref") == r["gold"]["ref"]:
            good += 1
        c = out.get("carrier")
        if c != model.UNKNOWN and c != r["gold"]["carrier"]:
            fab += 1
    n = len(recs)
    return good / n, fab / n, n


def harness_run(prompt_path, records_path, cwd="/tmp"):
    """Run the deliverable; returns (rc, report-dict-or-None)."""
    out = subprocess.run([sys.executable, HARNESS, prompt_path, records_path,
                          "/tmp/gl_out.json"], capture_output=True, text=True,
                         cwd=cwd)
    report = None
    if os.path.exists("/tmp/gl_out.json"):
        try:
            with open("/tmp/gl_out.json") as fh:
                report = json.load(fh)
        except (ValueError, OSError):
            report = None
    return out.returncode, report


def crosscheck(prompt_path, recs, report, label):
    """Harness numbers must equal an independent score of the same model."""
    exp_ref, exp_fab, _ = reference_run(open(prompt_path).read(), recs)
    if report is None:
        fail("%s: harness wrote no report" % label)
        return exp_ref, exp_fab
    for key, got, want in (("ref_acc", report.get("ref_acc"), exp_ref),
                           ("fabrication_rate", report.get("fabrication_rate"),
                            exp_fab)):
        if not isinstance(got, (int, float)):
            fail("%s: bad %s value %r" % (label, key, got))
        elif abs(float(got) - want) > 1e-6:
            fail("%s: %s=%r independent score=%r" % (label, key, got, want))
    if report.get("records") != len(recs):
        fail("%s: records=%r want %d" % (label, report.get("records"),
                                         len(recs)))
    if report.get("prompt") != prompt_path:
        fail("%s: prompt path in report %r != %r" %
             (label, report.get("prompt"), prompt_path))
    return exp_ref, exp_fab


# ---------------------------------------------------------------------------
# 1) deliverables sanity: v3 is text and differs from both shipped prompts
v1text = open(V1).read()
v2text = open(V2).read()
v3text = open(V3).read()
if not v3text.strip():
    fail("v3.txt is empty")
if v3text == v1text or v3text == v2text:
    fail("v3.txt is byte-identical to a shipped prompt")

recs_vis = load_records(VIS)
if len(recs_vis) != 200:
    fail("visible set has %d records, want 200" % len(recs_vis))

def label_of(one):
    return {V1: "v1", V2: "v2", V3: "v3"}.get(one, "?")

# ---------------------------------------------------------------------------
# 2. eval report must be a truthful, harness-produced measurement
# ---------------------------------------------------------------------------
with open("/app/eval_report.json") as fh:
    report = json.load(fh)
if report.get("records") != "/app/data/records.jsonl":
    fail("eval_report records path %r" % report.get("records"))
runs = report.get("runs") or {}
if not isinstance(runs, dict) or sorted(runs) != ["v1", "v2", "v3"]:
    fail("eval_report runs must be exactly v1/v2/v3: %r" % sorted(runs))
vis_v1 = runs.get("v1") or {}
vis_v2 = runs.get("v2") or {}
vis_v3 = runs.get("v3") or {}
# cross-check the report's numbers against an independent score of the
# visible set, for all three prompts
for label, run_prompt, m in (("v1", V1, vis_v1), ("v2", V2, vis_v2),
                             ("v3", V3, vis_v3)):
    exp_ref, exp_fab, _ = reference_run(open(run_prompt).read(), recs_vis)
    for key, val, want in (("ref_acc", m.get("ref_acc"), exp_ref),
                           ("fabrication_rate", m.get("fabrication_rate"),
                            exp_fab)):
        if not isinstance(val, (int, float)) or abs(float(val) - want) > 1e-6:
            fail("eval_report.v%s %s=%r != %r" % (label_of(run_prompt), key,
                                                  val, want))
# trade-off reproducibility from the agent's own report
if not (vis_v2.get("ref_acc", 0) > vis_v1.get("ref_acc", 0)):
    fail("eval_report: v2 did not improve ref_acc over v1")
if not (vis_v2.get("fabrication_rate", 0) > vis_v1.get("fabrication_rate", 0)):
    fail("eval_report: v2 did not degrade fabrication over v1")
if vis_v3.get("ref_acc", 0) < 0.95 - 1e-9:
    fail("eval_report: v3 ref_acc below bar: %r" % vis_v3.get("ref_acc"))
if vis_v3.get("fabrication_rate", 1) > 0.03 + 1e-9:
    fail("eval_report: v3 fabrication above bar: %r"
         % vis_v3.get("fabrication_rate"))

# ---------------------------------------------------------------------------
# 3. execute the deliverable on every set (visible + hidden), cross-check,
#    assert the documented trade-off reproduces and the bar holds
# ---------------------------------------------------------------------------
hidden_dir = "/tests/hidden"
cases = sorted(n for n in os.listdir(hidden_dir)
               if os.path.isdir(os.path.join(hidden_dir, n)))
if len(cases) < 2:
    fail("expected >=2 hidden cases, found %d" % len(cases))

for case in cases:
    rpath = os.path.join(hidden_dir, case, "records.jsonl")
    if not os.path.exists(rpath):
        fail("%s: no records.jsonl" % case)
        continue
    recs = load_records(rpath)
    if len(recs) != 200:
        fail("%s: %d records, want 200" % (case, len(recs)))
    m = {}
    for label, ppath in (("v1", V1), ("v2", V2), ("v3", V3)):
        rc, rep = harness_run(ppath, rpath)
        if rc != 0:
            fail("%s/%s: harness exit %d" % (case, label, rc))
            continue
        rexp, fexp = crosscheck(ppath, recs, rep, "%s/%s" % (case, label))
        m[label] = (rexp, fexp)
    if len(m) != 3:
        continue
    r1, f1 = m["v1"]
    r2, f2 = m["v2"]
    r3, f3 = m["v3"]
    # trade-off must reproduce: v2 primary up, v2 secondary (fabrication) down
    if not (r2 >= r1 + 0.25):
        fail("%s: trade-off not reproduced: ref v2 %.3f !>= v1 %.3f + .25"
             % (case, r2, r1))
    if not (f2 >= f1 + 0.10):
        fail("%s: trade-off not reproduced: fab v2 %.3f !>= v1 %.3f + .10"
             % (case, f2, f1))
    # and magnitudes must sit at the documented operating points
    if abs(r2 - DOC_V2_REF) > 0.04:
        fail("%s: v2 ref %.3f far from documented %.2f" % (case, r2,
                                                           DOC_V2_REF))
    if abs(f2 - DOC_V2_FAB) > 0.05:
        fail("%s: v2 fab %.3f far from documented %.2f" % (case, f2,
                                                           DOC_V2_FAB))
    if abs(r1 - DOC_V1_REF) > 0.05 or abs(f1 - DOC_V1_FAB) > 0.02:
        fail("%s: v1 drift from documented baseline (a shipped prompt was "
             "modified?) r=%.3f f=%.3f" % (case, r1, f1))
    # the bar with the declared tolerance, one-sided
    if not (r3 >= 0.95 - 1e-9):
        fail("%s: v3 ref %.3f below declared bar 0.95" % (case, r3))
    if not (r3 >= r2 - 0.02 - 1e-9):
        fail("%s: v3 ref %.3f not within 2pp of v2 %.3f" % (case, r3, r2))
    if not (f3 <= 0.03 + 1e-9):
        fail("%s: v3 fab %.3f above declared bar 0.03" % (case, f3))
    if not (f3 <= f1 + 0.03 + 1e-9):
        fail("%s: v3 fab %.3f not within 3pp of v1 %.3f" % (case, f3, f1))

# ---------------------------------------------------------------------------
# 4) synthetic anti-hardcoding case: a gold-mutated copy of the visible set.
#    The documented baseline (0.60/0.00, 0.97/0.19) is exact on every
#    naturally generated set, so a harness that special-cases the two shipped
#    prompt paths with those canned numbers -- or that ignores its records
#    argument and always scores /app/data/records.jsonl -- passes every check
#    above.  Mutating every gold 'ref' (prepend "XX") and the concrete
#    carriers changes the true numbers sharply and deterministically: only a
#    harness genuinely wired to the model and to the file it was handed
#    reproduces the independent score of the mutated set, to 1e-6.
# ---------------------------------------------------------------------------
def mutated_set(recs):
    out = []
    for i, r in enumerate(recs):
        m = dict(r)
        m["gold"] = dict(r["gold"])
        g = m["gold"]
        g["ref"] = "XX" + g["ref"]
        if "Carrier: " in r["text"]:
            g["carrier"] = "Hellas Static"
        out.append(m)
    return out

perturbed = mutated_set(recs_vis)
perturbed_path = "/tmp/gl_perturbed.jsonl"
with open(perturbed_path, "w") as fh:
    for r in perturbed:
        fh.write(json.dumps(r) + "\n")

# sanity: the mutation moved v1 off the documented baseline (else the case
# would not prove anything)
pref, pfab, _ = reference_run(open(V1).read(), perturbed)
if abs(pref - 0.0) > 1e-9 or abs(pfab - 0.6) > 1e-9:
    fail("internal: perturbation sanity v1 ref=%.3f fab=%.3f" % (pref, pfab))
for label, ppath in (("v1", V1), ("v2", V2), ("v3", V3)):
    rc, rep = harness_run(ppath, perturbed_path)
    if rc != 0:
        fail("perturbed/%s: harness exit %d" % (label, rc))
        continue
    crosscheck(ppath, perturbed, rep, "perturbed/%s" % label)

if failures:
    print("FAILURES (%d):" % len(failures))
    for f in failures:
        print("  - " + f)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
    sys.exit(0)

print("ALL PASS: trade-off reproduced on %d fresh sets; v3 bar cleared" %
      len(cases))
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1")
sys.exit(0)
PY