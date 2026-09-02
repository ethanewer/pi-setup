#!/bin/bash
# Oracle for fen-lantern: author the task wiring (config + harness runner),
# then RUN the runner on the visible fixture to produce the baseline result.
# Never reads /tests.
set -eu

CFG="/app/tasks/wetland_calls.yaml"
RUNNER="/app/run_task.py"
RESULT="/app/results/wetland_calls/baseline.json"

mkdir -p /app/tasks /app/results/wetland_calls

# ---- 1. The task configuration: choices in the model's internal class order.
cat > "$CFG" <<'YAML'
task_name: wetland_calls
model_path: /app/model/fen_scout.json
run_name: baseline
choices:
  - bittern
  - crake
  - grebe
  - warbler
doc_to_choice:
  bittern: 0
  crake: 1
  grebe: 2
  warbler: 3
prompt_template: |
  Field note: {note}

  Which wetland species made this call?
  [0] bittern   [1] crake   [2] grebe   [3] warbler
YAML

# ---- 2. The harness runner (uses the installed fen_eval package).
cat > "$RUNNER" <<'PY'
#!/usr/bin/env python3
"""Run the wetland_calls classification task through the fen_eval harness.

Usage: python3 /app/run_task.py <task_yaml> <docs_jsonl> <labels_json> <out_json>
"""
import json
import sys

import fen_eval


def main(argv):
    if len(argv) != 5:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    spec = fen_eval.load_task_spec(argv[1])
    model = fen_eval.load_model(spec.model_path)
    docs = fen_eval.load_docs(argv[2])
    labels = fen_eval.load_labels(argv[3])
    if docs:
        fen_eval.render_prompt(spec.prompt_template, docs[0])
    result = fen_eval.evaluate(
        model,
        docs,
        labels,
        choices=spec.choices,
        gold_map=spec.doc_to_choice,
        task_name=spec.task_name,
        run_name=spec.run_name,
    )
    with open(argv[4], "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
PY
chmod +x "$RUNNER"

# ---- 3. Run the visible fixture to produce the baseline result.
python3 "$RUNNER" "$CFG" /app/data/wetland_docs.jsonl /app/data/wetland_labels.json "$RESULT"

echo "solve.sh done -> $CFG, $RUNNER, $RESULT"
ls -l "$CFG" "$RUNNER" "$RESULT"
