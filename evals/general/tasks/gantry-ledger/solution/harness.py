#!/usr/bin/env python3
"""gantry-ledger evaluation harness (reference implementation).

Usage:
    python3 /app/harness.py <prompt.txt> <records.jsonl> <out.json>

Evaluates a prompt draft against a record set using the deterministic local
model and writes the two-metric report (ref_acc, fabrication_rate). Pure
stdlib; runs from any working directory.
"""
import json
import sys


def main():
    if len(sys.argv) != 4:
        print("usage: harness.py <prompt.txt> <records.jsonl> <out.json>")
        return 2
    prompt_path, records_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

    sys.path.insert(0, "/app")
    import model

    prompt = open(prompt_path, encoding="utf-8").read()
    records = []
    with open(records_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                records.append(json.loads(line))

    good_refs = 0
    fabrications = 0
    for rec in records:
        out = model.extract(prompt, rec["text"])
        if out.get("ref") == rec["gold"]["ref"]:
            good_refs += 1
        carrier = out.get("carrier")
        if carrier != model.UNKNOWN and carrier != rec["gold"]["carrier"]:
            fabrications += 1

    n = len(records)
    report = {
        "prompt": prompt_path,
        "records": n,
        "ref_acc": good_refs / n if n else 0.0,
        "fabrication_rate": fabrications / n if n else 0.0,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())