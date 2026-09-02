#!/bin/bash
# Oracle for keel-bight: write the plan-record emitter program, then RUN it on
# the visible fixture to produce /app/plans.jsonl and /app/summary.json.
# Never reads /tests.
set -eu

SOLVER="/app/solve.py"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Dispatch plan record emitter for the consolidator relay.

Usage: python3 solve.py <requests_jsonl> <out_plans_jsonl> <out_summary_json>
"""
import json
import sys

VALID_PRIORITIES = ("standard", "expedite")


def is_str(x):
    return isinstance(x, str) and x != ""


def is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def parse_request(line):
    """Return a normalized plan record dict, or None if the line is invalid."""
    try:
        obj = json.loads(line)
    except Exception:
        return None
    if not isinstance(obj, dict):
        return None
    rid, batch, spec = obj.get("id"), obj.get("batch"), obj.get("spec")
    if not is_str(rid) or not is_str(batch) or not isinstance(spec, dict):
        return None
    vessel, teu = spec.get("vessel"), spec.get("teu")
    days, priority = spec.get("transit_days"), spec.get("priority")
    oversize = spec.get("oversize", False)
    if not isinstance(vessel, str):
        return None
    if not is_num(teu) or teu < 0:
        return None
    if not is_int(days) or days < 1:
        return None
    if priority not in VALID_PRIORITIES:
        return None
    if not isinstance(oversize, bool):
        return None
    code = ("EXP" if priority == "expedite" else "STD") + ("-X" if oversize else "")
    shape = {
        "capacity": round(float(teu), 2),
        "days": days,
        "code": code,
        "vessel": vessel,
    }
    return {"id": rid, "batch": batch, "shape": shape}


def main():
    req_path, plans_path, summary_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(req_path, "r", encoding="utf-8") as fh:
        raw = fh.read()
    lines = raw.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    plans = []
    batches = {}
    for line in lines:
        rec = parse_request(line)
        if rec is None:
            continue
        plans.append(rec)
        batches[rec["batch"]] = batches.get(rec["batch"], 0) + 1
    summary = {
        "requests": len(lines),
        "plans": len(plans),
        "rejected": len(lines) - len(plans),
        "expedited": sum(1 for r in plans if r["shape"]["code"].startswith("EXP")),
        "batches": {k: batches[k] for k in sorted(batches)},
    }
    with open(plans_path, "w", encoding="utf-8") as fh:
        for rec in plans:
            fh.write(json.dumps(rec, separators=(",", ":")))
            fh.write("\n")
    with open(summary_path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/requests.jsonl /app/plans.jsonl /app/summary.json

echo "solve.sh done -> $SOLVER, /app/plans.jsonl, /app/summary.json"
ls -l "$SOLVER" /app/plans.jsonl /app/summary.json
