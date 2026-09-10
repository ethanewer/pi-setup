#!/usr/bin/env bash
# Oracle for gantry-ledger: installs the eval harness, the third prompt
# version, and a real eval report produced by running the harness against the
# shipped model and records. Never reads /tests and never hardcodes metrics.
set -eu

mkdir -p /app/prompts

cp /solution/harness.py /app/harness.py
chmod +x /app/harness.py
cp /solution/v3.txt /app/prompts/v3.txt

# Run the harness for real on the shipped reference set: v1, v2, then v3.
python3 /app/harness.py /app/prompts/v1.txt /app/data/records.jsonl /tmp/r_v1.json
python3 /app/harness.py /app/prompts/v2.txt /app/data/records.jsonl /tmp/r_v2.json
python3 /app/harness.py /app/prompts/v3.txt /app/data/records.jsonl /tmp/r_v3.json

# Assemble the report from the measured runs (never hand-written numbers).
python3 - <<'PY'
import json

runs = {}
for label in ("v1", "v2", "v3"):
    with open("/tmp/r_%s.json" % label) as fh:
        r = json.load(fh)
    runs[label] = {"ref_acc": r["ref_acc"],
                   "fabrication_rate": r["fabrication_rate"]}

report = {
    "records": "/app/data/records.jsonl",
    "runs": runs,
}
with open("/app/eval_report.json", "w") as fh:
    json.dump(report, fh, indent=2)
print("eval_report written:", report)
PY

echo "oracle complete"
cat /app/eval_report.json