#!/bin/bash
# Oracle for velvet-quay: author the as-of audit program, then RUN it on the
# visible fixtures to produce /app/audit.json. Never reads /tests.
set -eu

# ---- 1. The audit program (this IS the work) --------------------------------
cat > /app/audit.py <<'PY'
#!/usr/bin/env python3
"""As-of charter ledger audit.

Usage:
    python3 audit.py <charters.jsonl> <audit.txt> <output.json>

Applies every amendment whose effective_on is <= the as-of date (latest
effective_on wins, later list position breaks ties), then classifies each
charter against the as-of date.
"""
import json
import sys
from datetime import date

AMENDABLE = ("start_on", "end_on", "terminated_on")


def to_date(value):
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def load_records(path):
    """Returns (records, malformed_count). Malformed lines are counted, ignored."""
    records, malformed = [], 0
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                malformed += 1
                continue
            ok = isinstance(obj, dict)
            if ok:
                cid, vessel = obj.get("charter_id"), obj.get("vessel")
                signed, start = to_date(obj.get("signed_on")), to_date(obj.get("start_on"))
                ok = (isinstance(cid, str) and cid
                      and isinstance(vessel, str) and vessel
                      and signed is not None and start is not None)
            if not ok:
                malformed += 1
                continue
            raw_end, raw_term = obj.get("end_on"), obj.get("terminated_on")
            end = to_date(raw_end) if raw_end is not None else None
            term = to_date(raw_term) if raw_term is not None else None
            if (raw_end is not None and end is None) or \
               (raw_term is not None and term is None):
                malformed += 1
                continue
            amds = obj.get("amendments")
            records.append({
                "charter_id": cid, "vessel": vessel,
                "signed_on": signed, "start_on": start,
                "end_on": end, "terminated_on": term,
                "amendments": amds if isinstance(amds, list) else [],
            })
    return records, malformed


def fields_as_of(rec, day):
    """Apply amendments with effective_on <= day; latest effective_on wins,
    later list position breaks ties. Value null clears the field."""
    chosen = {}
    for i, am in enumerate(rec["amendments"]):
        if not isinstance(am, dict):
            continue
        field = am.get("field")
        if field not in AMENDABLE:
            continue
        eff = to_date(am.get("effective_on"))
        if eff is None or eff > day:
            continue
        val = am.get("value")
        if val is not None:
            val = to_date(val)
            if val is None:
                continue
        key = (eff, i)
        if field not in chosen or key > chosen[field][0]:
            chosen[field] = (key, val)
    start = chosen["start_on"][1] if "start_on" in chosen else rec["start_on"]
    end = chosen["end_on"][1] if "end_on" in chosen else rec["end_on"]
    term = chosen["terminated_on"][1] if "terminated_on" in chosen else rec["terminated_on"]
    return start, end, term


def main():
    if len(sys.argv) != 4:
        print("usage: audit.py <charters.jsonl> <audit.txt> <output.json>",
              file=sys.stderr)
        return 2
    ledger_path, audit_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

    as_of = None
    with open(audit_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            if key.strip() == "as_of":
                as_of = to_date(value.strip())
    if as_of is None:
        print("audit.txt must contain as_of=YYYY-MM-DD", file=sys.stderr)
        return 1

    records, malformed = load_records(ledger_path)

    active_ids, pending_ids, open_ended_ids, by_vessel = [], [], [], {}
    for rec in records:
        signed = rec["signed_on"]
        start, end, term = fields_as_of(rec, as_of)
        is_active = (signed <= as_of and start <= as_of
                     and (end is None or as_of <= end)
                     and (term is None or as_of < term))
        if is_active:
            active_ids.append(rec["charter_id"])
            open_ended_ids.append(rec["charter_id"]) if end is None else None
            by_vessel[rec["vessel"]] = by_vessel.get(rec["vessel"], 0) + 1
        elif signed <= as_of and start > as_of:
            pending_ids.append(rec["charter_id"])

    result = {
        "as_of": as_of.isoformat(),
        "active_ids": sorted(active_ids),
        "active_count": len(active_ids),
        "pending_ids": sorted(pending_ids),
        "open_ended_ids": sorted(open_ended_ids),
        "by_vessel": {k: by_vessel[k] for k in sorted(by_vessel)},
        "malformed": malformed,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
    print("AUDIT_OK active=%d pending=%d" % (len(active_ids), len(pending_ids)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x /app/audit.py

# ---- 2. Produce the visible deliverable by actually running ------------------
python3 /app/audit.py /app/charters.jsonl /app/audit.txt /app/audit.json

echo "solve.sh done"
ls -l /app/audit.py /app/audit.json
