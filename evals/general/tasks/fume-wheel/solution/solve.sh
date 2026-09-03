#!/bin/bash
# Oracle for fume-wheel: write the real adjudication engine
# /app/adjudicate.py and run it on the visible fixtures to produce the
# report deliverable /app/adjudication.json. Pure stdlib Python.
# Never reads /tests.
set -eu

cat > /app/adjudicate.py <<'PYEOF'
#!/usr/bin/env python3
"""Deneb Slip Cooperative claims adjudication engine (integer cents)."""
import datetime
import json
import sys


def main(argv):
    if len(argv) != 3:
        print("usage: adjudicate.py <policy.json> <claims.jsonl> <out.json>",
              file=sys.stderr)
        return 2
    policy_path, claims_path, out_path = argv

    with open(policy_path) as fh:
        policy = json.load(fh)
    start = datetime.date.fromisoformat(policy["policy_start"])
    end = datetime.date.fromisoformat(policy["policy_end"])
    deductible = policy["deductible_cents"]
    coinsurance = policy["coinsurance_percent"]
    per_claim_cap = policy["per_claim_cap_cents"]
    aggregate_cap = policy["annual_aggregate_cap_cents"]
    excluded = set(policy["excluded_categories"])

    claims = []
    with open(claims_path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            claims.append(json.loads(line))

    rows = []  # [index, decision, payable_cents, reason_codes]
    eligible = []

    for idx, claim in enumerate(claims):
        category = claim["category"]
        day = datetime.date.fromisoformat(claim["date"])
        if category in excluded:
            rows.append([idx, "denied", 0, ["excluded_category"]])
            continue
        if not (start <= day <= end):
            rows.append([idx, "denied", 0, ["out_of_window"]])
            continue
        covered = max(0, claim["amount_cents"] - deductible)
        payable_pre_cap = (covered * (100 - coinsurance)) // 100
        payable = min(payable_pre_cap, per_claim_cap)
        eligible.append([idx, covered, payable_pre_cap, payable])

    # Annual aggregate cap: stable sort by id, running total, truncate.
    eligible.sort(key=lambda row: claims[row[0]]["id"])
    paid_total = 0
    exhausted = False
    for idx, covered, payable_pre_cap, payable in eligible:
        if exhausted:
            rows.append([idx, "approved_zero", 0, ["aggregate_exhausted"]])
            continue
        reasons = []
        if claims[idx]["amount_cents"] > covered:
            reasons.append("deductible_applied")
        if covered > 0 and coinsurance > 0:
            reasons.append("coinsurance_applied")
        if payable_pre_cap > per_claim_cap:
            reasons.append("per_claim_cap_applied")
        if paid_total + payable <= aggregate_cap:
            paid = payable
            paid_total += paid
        else:
            paid = aggregate_cap - paid_total
            paid_total = aggregate_cap
            reasons.append("aggregate_truncated")
        if not reasons:
            reasons.append("eligible")
        rows.append([idx, "approved", paid, reasons])
        if paid_total >= aggregate_cap:
            exhausted = True

    rows.sort(key=lambda row: (claims[row[0]]["id"], row[0]))
    result = {
        "claims": [
            {"id": claims[i]["id"], "decision": decision,
             "payable_cents": paid, "reason_codes": codes}
            for i, decision, paid, codes in rows
        ],
        "aggregate": {
            "paid_cents": sum(paid for _, _, paid, _ in rows),
            "cap_remaining_cents": aggregate_cap
            - sum(paid for _, _, paid, _ in rows),
        },
    }
    with open(out_path, "w") as fh:
        json.dump(result, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PYEOF

chmod 0755 /app/adjudicate.py

python3 /app/adjudicate.py /app/policy.json /app/claims.jsonl /app/adjudication.json

echo "solve.sh done"
ls -l /app/adjudicate.py /app/adjudication.json
cat /app/adjudication.json