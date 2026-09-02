#!/usr/bin/env python3
"""Independent reference recomputation for tb3-harbor-ledger.

Replays the deliverable CLI /app/adjudicate.py on the visible fixtures and
on every hidden (policy.json, claims.jsonl) bundle under /tests/hidden,
comparing each produced JSON against this probe's OWN implementation of the
documented pipeline (eligibility -> deductible -> coinsurance floor ->
per-claim cap -> annual aggregate in stable id order). Also requires the
report deliverable /app/adjudication.json to equal the visible
recomputation. Exit 0 only when every comparison passes.
"""
import datetime
import json
import os
import subprocess
import sys

ADJUDICATE = "/app/adjudicate.py"
REPORT = "/app/adjudication.json"

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg)


def load_policy(path):
    with open(path) as fh:
        p = json.load(fh)
    return {
        "start": datetime.date.fromisoformat(p["policy_start"]),
        "end": datetime.date.fromisoformat(p["policy_end"]),
        "deductible": int(p["deductible_cents"]),
        "coinsurance": int(p["coinsurance_percent"]),
        "per_claim_cap": int(p["per_claim_cap_cents"]),
        "aggregate_cap": int(p["annual_aggregate_cap_cents"]),
        "excluded": set(p["excluded_categories"]),
    }


def load_claims(path):
    claims = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            claims.append(json.loads(line))
    return claims


def reference(policy, claims):
    """Reference adjudication: eligibility, deductible, coinsurance floor,
    per-claim cap, then annual aggregate in stable ascending-id order."""
    start, end = policy["start"], policy["end"]
    deductible = policy["deductible"]
    coinsurance = policy["coinsurance"]
    per_claim_cap = policy["per_claim_cap"]
    aggregate_cap = policy["aggregate_cap"]
    excluded = policy["excluded"]

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

    paid_total = 0
    exhausted = False
    eligible.sort(key=lambda r: claims[r[0]]["id"])  # stable: ties keep order
    for idx, covered, payable_pre_cap, payable in eligible:
        if exhausted:
            rows.append([idx, "approved_zero", 0, ["aggregate_exhausted"]])
            continue
        codes = []
        if claims[idx]["amount_cents"] > covered:
            codes.append("deductible_applied")
        if covered > 0 and coinsurance > 0:
            codes.append("coinsurance_applied")
        if payable_pre_cap > per_claim_cap:
            codes.append("per_claim_cap_applied")
        if paid_total + payable <= aggregate_cap:
            paid = payable
            paid_total += paid
        else:
            paid = aggregate_cap - paid_total
            paid_total = aggregate_cap
            codes.append("aggregate_truncated")
        if not codes:
            codes.append("eligible")
        rows.append([idx, "approved", paid, codes])
        if paid_total >= aggregate_cap:
            exhausted = True

    rows.sort(key=lambda r: (claims[r[0]]["id"], r[0]))
    paid_total = sum(r[2] for r in rows)
    return {
        "claims": [
            {"id": claims[i]["id"], "decision": decision,
             "payable_cents": paid, "reason_codes": codes}
            for i, decision, paid, codes in rows
        ],
        "aggregate": {
            "paid_cents": paid_total,
            "cap_remaining_cents": aggregate_cap - paid_total,
        },
    }


def run_cli(policy_path, claims_path, out_path):
    try:
        return subprocess.run(
            [sys.executable, ADJUDICATE, policy_path, claims_path, out_path],
            capture_output=True, text=True, timeout=60)
    except Exception as exc:
        fail("executing %s raised %s" % (ADJUDICATE, exc))
        return None


def check_case(label, policy_path, claims_path):
    try:
        want = reference(load_policy(policy_path), load_claims(claims_path))
    except Exception as exc:
        fail("%s: reference recompute failed: %s" % (label, exc))
        return
    out = "/tmp/harbor_probe_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = run_cli(policy_path, claims_path, out)
    if r is None:
        return
    if r.returncode != 0:
        fail("%s: adjudicate.py exit %s; stderr: %s"
             % (label, r.returncode, (r.stderr or "").strip()[:200]))
        return
    try:
        with open(out) as fh:
            got = json.load(fh)
    except Exception as exc:
        fail("%s: agent output not readable JSON: %s" % (label, exc))
        return
    if got != want:
        fail("%s: output differs from reference recomputation" % label)
        print("  want:", json.dumps(want)[:400])
        print("  got :", json.dumps(got)[:400])


def main():
    # 1. Visible fixtures executed through the deliverable CLI.
    check_case("visible", "/app/policy.json", "/app/claims.jsonl")

    # 2. The report deliverable must equal the visible recomputation.
    want_visible = reference(load_policy("/app/policy.json"),
                             load_claims("/app/claims.jsonl"))
    try:
        with open(REPORT) as fh:
            got_report = json.load(fh)
        if got_report != want_visible:
            fail("adjudication.json differs from the visible recomputation")
    except Exception as exc:
        fail("adjudication.json unreadable: %s" % exc)

    # 3. Hidden (policy, claims) bundles through the deliverable CLI.
    hidden = "/tests/hidden"
    if not os.path.isdir(hidden):
        fail("hidden directory missing")
        return 1 if failures else 0
    bundles = []
    for p in sorted(os.listdir(hidden)):
        bdir = os.path.join(hidden, p)
        if (os.path.isdir(bdir)
                and os.path.isfile(os.path.join(bdir, "policy.json"))
                and os.path.isfile(os.path.join(bdir, "claims.jsonl"))):
            bundles.append(p)
    if not bundles:
        fail("no hidden bundles present")
    for name in bundles:
        check_case("hidden:%s" % name,
                   os.path.join(hidden, name, "policy.json"),
                   os.path.join(hidden, name, "claims.jsonl"))

    if failures:
        print("probe failures: %d" % len(failures))
        return 1
    print("probe: all comparisons passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())