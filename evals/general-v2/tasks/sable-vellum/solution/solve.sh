#!/bin/bash
# Oracle for sable-vellum: author the task config + HTTP driver, then RUN the
# driver over loopback HTTP on the visible corpus to produce the result file.
# Never reads /tests.
set -eu

YAML="/app/task_vellum.yaml"
DRIVER="/app/run_cards.py"
OUT="/app/results/card_sortis/visible.json"

# ---- 1. The task configuration (choices order defines the gold indices).
cat > "$YAML" <<'YML'
task_name: card_sortis
n_classes: 3
choices: [herb, tree, moss]
model_path: /app/model/vex_nano.json
query_column: excerpt
title_column: title
doc_to_choice: gold_label
prompt_template: |
  Archive card: {title}
  Excerpt: {excerpt}

  Which of these three plant groups best matches the card?
  [0] herb   [1] tree   [2] moss
YML

# ---- 2. The generic HTTP driver (URLs from argv, no hard-coded fixtures).
cat > "$DRIVER" <<'PY'
#!/usr/bin/env python3
"""sable-vellum eval driver: fetch docs+labels over HTTP, score with
vellum_eval, write the result JSON."""
import argparse
import json

from vellum_eval import classification, load_model, load_task_spec
from vellum_eval.remote import fetch_json, fetch_jsonl


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task_yaml")
    ap.add_argument("docs_url")
    ap.add_argument("labels_url")
    ap.add_argument("out_json")
    args = ap.parse_args()

    spec = load_task_spec(args.task_yaml)
    model = load_model(spec.model_path)
    docs = fetch_jsonl(args.docs_url)
    labels = fetch_json(args.labels_url)
    result = classification(docs, labels, model, spec)

    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, sort_keys=True)
    print(json.dumps({"task": result["task"], "n": result["n"],
                      "correct": result["correct"],
                      "accuracy": result["accuracy"]}))


if __name__ == "__main__":
    main()
PY
chmod +x "$DRIVER"

# ---- 3. Serve the visible corpus over loopback HTTP and run the driver.
PORT=8821
python3 -m http.server "$PORT" --directory /app/corpus >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
sleep 1
mkdir -p /app/results/card_sortis
python3 "$DRIVER" "$YAML" \
    "http://127.0.0.1:$PORT/docs.jsonl" \
    "http://127.0.0.1:$PORT/labels.json" \
    "$OUT"
kill "$SRV" 2>/dev/null || true

echo "solve.sh done -> $YAML, $DRIVER, $OUT"
python3 -c "import json;r=json.load(open('$OUT'));print('accuracy', r['accuracy'], 'n', r['n'])"
