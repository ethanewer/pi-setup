#!/usr/bin/env python3
"""gantry_judge -- the deployment's quality judge.

The deployment defines "good" deterministically for every record: a
summary is acceptable only when all four of the record's facts are
present and exact:

  * title      -- the record's ``title`` field
  * amount     -- the dollar figure in the FUNDING section
  * deadline   -- the ISO date in the FUNDING section
  * impact     -- the Impact: sentence in the JUSTIFICATION section

The extraction rules are the same rules any summariser should apply to the
record -- the facts are not secret, they sit in the record's own prose.
The job's output is judged by the same contract.

CLI:
  python3 gantry_judge.py RECORDS.jsonl SUMMARIES.jsonl [floor]

prints the pass rate and exits 0 when it meets the floor, 1 otherwise.
"""
import json
import re
import sys

AMOUNT_RE = re.compile(r'(\d[\d,]*\.\d{2})')
DATE_RE = re.compile(r'(\d{4}-\d{2}-\d{2})')
IMPACT_RE = re.compile(r'(Impact:[^.\n]*\.)')

REQUIRED = ("title", "amount", "deadline", "impact")


def section_text(record, head):
    for s in record.get("sections", []):
        if str(s.get("head", "")).upper() == head.upper():
            return s.get("text", "")
    return ""


def gold_facts(record):
    """The four facts the deployment considers authoritative for a record."""
    funding = section_text(record, "FUNDING")
    just = section_text(record, "JUSTIFICATION")
    m_amount = AMOUNT_RE.search(funding)
    m_date = DATE_RE.search(funding)
    m_impact = IMPACT_RE.search(just)
    return {
        "title": record.get("title", ""),
        "amount": m_amount.group(1) if m_amount else None,
        "deadline": m_date.group(1) if m_date else None,
        "impact": m_impact.group(0) if m_impact else None,
    }


def assess(record, summary):
    """True iff *summary* carries every fact of *record* verbatim."""
    gold = gold_facts(record)
    for key in REQUIRED:
        if summary.get(key) != gold[key]:
            return False
    return True


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    rec_path, sum_path = sys.argv[1], sys.argv[2]
    floor = float(sys.argv[3]) if len(sys.argv) > 3 else None

    with open(rec_path) as fh:
        records = [json.loads(line) for line in fh if line.strip()]
    with open(sum_path) as fh:
        summaries = [json.loads(line) for line in fh if line.strip()]
    by_id = {s.get("id"): s for s in summaries}

    ok = 0
    missing = 0
    for r in records:
        s = by_id.get(r["id"])
        if s is None:
            missing += 1
            continue
        if assess(r, s):
            ok += 1
    total = len(records)
    rate = ok / total if total else 0.0
    print("judge: pass=%d/%d (%.3f) floor=%s missing=%d" % (
        ok, total, rate, floor, missing))
    if floor is not None and rate < floor:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())