#!/bin/bash
# Verifier for gantry-budget (executes-deliverable).
#
# Re-runs the job's /app/summarizer.py on every hidden deployment and
# asserts the full contract, minus the agent:
#
#   1. every record appears in the output exactly once, in input order;
#   2. every record was actually sent to the billed model (its id appears
#      in the run's ledger);
#   3. the run's total billed tokens -- recomputed authoritatively here
#      from the ledger prompt texts (1 token per word + 150 per request)
#      plus the serialised summaries -- stay within the deployment's
#      budget_tokens;
#   4. quality: at least quality_floor of the summaries carry every
#      judged fact of their record verbatim.
#
# The bill is recomputed from the ledger and the output file; nothing the
# job wrote into either is trusted, and nothing is imported from /app.
#
# The reward file is written on every exit path; any earlier content is
# always overwritten.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFY: verifier exited without writing a reward; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

if [ ! -f /app/summarizer.py ]; then
  echo "gantry-budget: missing deliverable /app/summarizer.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys

DELIV = "/app/summarizer.py"
HIDDEN = "/tests/hidden"
REQ_OVERHEAD = 150

AMOUNT_RE = re.compile(r'(\d[\d,]*\.\d{2})')
DATE_RE = re.compile(r'(\d{4}-\d{2}-\d{2})')
IMPACT_RE = re.compile(r'(Impact:[^.\n]*\.)')
FIELDS = ("title", "amount", "deadline", "impact")
FACTS = FIELDS

failures = []


def fail(msg):
    failures.append(msg)


def section_text(record, head):
    for s in record.get("sections", []):
        if str(s.get("head", "")).upper() == head.upper():
            return s.get("text", "")
    return ""


def gold_facts(record):
    fund = section_text(record, "FUNDING")
    just = section_text(record, "JUSTIFICATION")
    ma = AMOUNT_RE.search(fund)
    md = DATE_RE.search(fund)
    mi = IMPACT_RE.search(just)
    return {
        "title": record.get("title", ""),
        "amount": ma.group(1) if ma else None,
        "deadline": md.group(1) if md else None,
        "impact": mi.group(0) if mi else None,
    }


def assess(record, summary):
    gold = gold_facts(record)
    return all(summary.get(k) == gold[k] for k in FACTS)


def count_tokens(text):
    return len(text.split())


def load_jsonl(path):
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            out.append(json.loads(line))
    return out


cases = sorted(n for n in os.listdir(HIDDEN)
               if os.path.isdir(os.path.join(HIDDEN, n)))
if len(cases) < 2:
    fail("expected at least two hidden deployments, found %d" % len(cases))

base = "/tmp/gb"
shutil.rmtree(base, ignore_errors=True)
os.makedirs(base)

for case in cases:
    src = os.path.join(HIDDEN, case)
    cfg_path = os.path.join(src, "config.json")
    rec_path = os.path.join(src, "records.jsonl")
    if not (os.path.exists(cfg_path) and os.path.exists(rec_path)):
        fail("%s: missing config.json or records.jsonl" % case)
        continue
    with open(cfg_path) as fh:
        cfg = json.load(fh)
    budget = int(cfg.get("budget_tokens", 0))
    floor = float(cfg.get("quality_floor", 1.0))

    work = os.path.join(base, "%s_work" % case)
    shutil.copytree(src, work)
    out_p = os.path.join(base, "%s_out.jsonl" % case)
    ledger_p = os.path.join(base, "%s_ledger.jsonl" % case)

    env = dict(os.environ)
    env["BILLING_LEDGER_PATH"] = ledger_p
    r = subprocess.run(
        [sys.executable, DELIV, "--input", work, "--output", out_p],
        capture_output=True, text=True, env=env)
    if r.returncode != 0:
        fail("%s: deliverable exited %d: %s" %
             (case, r.returncode, r.stderr.strip()[:300]))
        continue

    # --- 1. output completeness + order --------------------------------
    try:
        summaries = load_jsonl(out_p)
    except Exception as exc:  # noqa: BLE001
        fail("%s: output is not valid JSON lines: %s" % (case, exc))
        continue
    records = load_jsonl(rec_path)
    want_ids = [rec["id"] for rec in records]
    got_ids = [s.get("id") for s in summaries]
    if got_ids != want_ids:
        diff_at = next((i for i, (a, b) in enumerate(zip(got_ids, want_ids))
                        if a != b), None)
        fail("%s: output ids/order mismatch: %d lines vs %d records"
             % (case, len(got_ids), len(want_ids)) +
             ("" if diff_at is None else
              " (first diff at index %d: %r vs %r)"
              % (diff_at, got_ids[diff_at], want_ids[diff_at])))

    # --- 2. every record really went to the model -------------------
    if not os.path.exists(ledger_p):
        fail("%s: no billing ledger was produced; records were never "
             "sent to the model" % case)
        billed = None
    else:
        ledger = load_jsonl(ledger_p)
        ledger_ids = set()
        for line in ledger:
            ledger_ids.update(line.get("ids", []))
        missing = [i for i in want_ids if i not in ledger_ids]
        if missing:
            fail("%s: %d records never sent to the model (e.g. %s)"
                 % (case, len(missing), missing[:5]))

        # --- 3. authorised bill vs the deployment budget ----
        billed_in = sum(count_tokens(line.get("prompt", "")) + REQ_OVERHEAD
                        for line in ledger)
        billed_out = sum(count_tokens(json.dumps(s, sort_keys=True))
                         for s in summaries)
        billed = billed_in + billed_out
        if billed > budget:
            fail("%s: billed %d tokens exceeds declared budget of %d "
                 "(%d in + %d out)" % (case, billed, budget,
                                       billed_in, billed_out))

    # --- 4. quality floor ------------------------------------------
    by_id = {s.get("id"): s for s in summaries}
    good = 0
    total = 0
    bad_samples = []
    for rec in records:
        s = by_id.get(rec["id"])
        total += 1
        if s is not None and assess(rec, s):
            good += 1
        elif len(bad_samples) < 4:
            bad_samples.append(rec["id"])
    rate = good / total if total else 0.0
    if rate + 1e-9 < floor:
        fail("%s: quality %.3f (%d/%d) below floor %s (e.g. %s)"
             % (case, rate, good, total, floor, bad_samples))

    print("case %-8s records=%d billed=%s budget=%d quality=%.3f floor=%s"
          % (case, len(want_ids), billed if billed is not None else "NA",
             budget, rate, floor))

if failures:
    print("FAILURES (%d):" % len(failures))
    for f in failures:
        print("  - " + f)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
else:
    print("ALL PASS: %d hidden deployments green" % len(cases))
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("1")
sys.exit(0)
PY