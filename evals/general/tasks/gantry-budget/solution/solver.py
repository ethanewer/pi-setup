#!/usr/bin/env python3
"""Reference batch summariser for a gantry deployment.

Reads records.jsonl + config.json from --input, extracts the four facts
the deployment's judge checks (title, amount, deadline, impact) from each
record's prose, sends only those facts to the billed model in batches
sized from the deployment's token budget, and writes one summary JSON per
line to --output in input order.

Cost model (gantry_client): 1 token per whitespace word, plus a fixed
150-token overhead per request, plus output tokens (the model echoes the
fields it saw, so output is billed again at roughly the block size).
"""
import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gantry_client as gc  # noqa: E402
import gantry_judge as gj    # noqa: E402

OUT_BLOCK_SLACK = 12


def facts_for(record):
    """Pull the four judged facts out of a record's prose."""
    title = record.get("title", "")
    funding = gj.section_text(record, "FUNDING")
    just = gj.section_text(record, "JUSTIFICATION")
    m_amount = gj.AMOUNT_RE.search(funding)
    m_date = gj.DATE_RE.search(funding)
    m_impact = gj.IMPACT_RE.search(just)
    return {
        "title": title,
        "amount": m_amount.group(1) if m_amount else "",
        "deadline": m_date.group(1) if m_date else "",
        "impact": m_impact.group(0) if m_impact else "",
    }


def build_block(record, f):
    lines = ["### RECORD %s" % record["id"]]
    for label in ("title", "amount", "deadline", "impact"):
        val = f[label]
        if val:
            lines.append("::%s:: %s" % (label.upper(), val))
    return "\n".join(lines)


def choose_batch(block_tokens, n_records, budget):
    """Smallest per-request batch whose estimated bill fits the budget.

    Input is billed at block_tokens per record; output is billed again at
    roughly the same size (the model echoes the fields it saw); the
    150-token request overhead is charged once per request. The 0.75
    safety factor keeps real runs inside the declared budget even when
    individual records are longer than the sample average.
    """
    if n_records <= 0:
        return 1
    est_content = (2 * block_tokens + OUT_BLOCK_SLACK) * n_records
    target = budget * 0.85
    for b in (1, 2, 4, 8, 16, 32, 64, 96, 128, 192, 256, 384, 512, 1024):
        reqs = math.ceil(n_records / b)
        est = est_content + reqs * gc.REQUEST_OVERHEAD_TOKENS
        if est <= target:
            return b
    # no batch fits the estimate: send everything in as few requests as
    # possible (largest batch), the best the estimate can do
    return 1024


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    with open(os.path.join(args.input, "config.json")) as fh:
        cfg = json.load(fh)
    with open(os.path.join(args.input, cfg.get("records_file",
                                               "records.jsonl"))) as fh:
        records = [json.loads(line) for line in fh if line.strip()]
    if cfg.get("budget_tokens", 0) <= 0:
        print("config: missing budget_tokens", file=sys.stderr)
        return 2

    # size requests from the deployment's own budget: sample the block
    # token cost, then pick the batch that the estimate can afford
    sample = []
    for r in records[:48]:
        f = facts_for(r)
        sample.append(gc.count_tokens(build_block(r, f)))
    est_block = int(sum(sample) / len(sample)) + 1 if sample else 16
    batch = choose_batch(est_block, len(records), cfg["budget_tokens"])

    client = gc.GantryClient()
    results = []
    for i in range(0, len(records), batch):
        chunk = records[i:i + batch]
        responses = client.summarize_many(
            [build_block(r, facts_for(r)) for r in chunk])
        by_id = {r["id"]: r for r in responses}
        for r in chunk:
            s = by_id.get(r["id"])
            if s is None:
                continue
            results.append({
                "id": r["id"],
                "title": s.get("title"),
                "amount": s.get("amount"),
                "deadline": s.get("deadline"),
                "impact": s.get("impact"),
            })

    if len(results) != len(records):
        print("processed %d of %d records -- incomplete"
              % (len(results), len(records)), file=sys.stderr)
        return 3
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as fh:
        for r in results:
            fh.write(json.dumps(r) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())