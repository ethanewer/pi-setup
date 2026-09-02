#!/bin/bash
# Real oracle for river-ledger. Writes the reconciler program, then RUNS it to
# produce the required deliverables. Does not read /tests and never cats
# precomputed answers.
set -eu

cat > /app/solve.py <<'PY'
import json
import sys

DEFAULT_INPUT = "/app/events.jsonl"
DEFAULT_STATE = "/app/state.json"
DEFAULT_AUDIT = "/app/audit.jsonl"


def main() -> int:
    if len(sys.argv) >= 4:
        inp, state_out, audit_out = sys.argv[1], sys.argv[2], sys.argv[3]
    else:
        inp, state_out, audit_out = DEFAULT_INPUT, DEFAULT_STATE, DEFAULT_AUDIT

    balance: dict = {}
    seen_ids = set()
    audit = []

    with open(inp, "r", encoding="utf-8") as handle:
        for lineno, raw in enumerate(handle, 1):
            line = raw.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except (ValueError, TypeError):
                audit.append({"kind": "malformed", "line": lineno})
                continue
            if not isinstance(rec, dict):
                audit.append({"kind": "malformed", "line": lineno})
                continue
            if not all(k in rec for k in ("id", "account", "delta")):
                audit.append({"kind": "malformed", "line": lineno})
                continue
            eid = rec["id"]
            account = rec["account"]
            delta = rec["delta"]
            if not isinstance(delta, (int, float)):
                audit.append({"kind": "malformed", "line": lineno})
                continue
            if eid in seen_ids:
                audit.append({"kind": "duplicate", "id": eid})
                continue
            seen_ids.add(eid)
            if rec.get("correction") is True:
                balance[account] = 0.0
                audit.append({"kind": "correction", "id": eid})
            balance[account] = balance.get(account, 0.0) + delta

    state = {account: balance[account] for account in sorted(balance)}
    with open(state_out, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2)
    with open(audit_out, "w", encoding="utf-8") as handle:
        for entry in audit:
            handle.write(json.dumps(entry) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x /app/solve.py
# Run the program on the visible journal to emit the required artifacts.
python3 /app/solve.py /app/events.jsonl /app/state.json /app/audit.jsonl