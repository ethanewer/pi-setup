#!/usr/bin/env python3
"""granite-inlet model-evaluation driver (author-authored).

Runs a registered harness task over a local fixture or a fresh dataset and
writes a canonical per-task JSON result under /app/results/<task>/<run>.json.

Usage:
  wire_cli.py classify <spec.yaml> <docs.jsonl> <labels.json> <out.json>
  wire_cli.py retrieval <spec.yaml> <queries.jsonl> <out.json>
  wire_cli.py describe <spec.yaml>
"""
import json
import os
import sys

sys.path.insert(0, "/app/harness")
from granite_eval import (
    load_task_spec,
    load_model,
    classification,
    retrieval,
)

MODEL_NAME = "cd-nano-0.3"
DEFAULT_RUN = "sprint_07"


def read_lines(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def write_json(path, obj):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def cmd_classify(spec_path, docs_path, labels_path, out_path, run):
    spec = load_task_spec(spec_path)
    docs = read_lines(docs_path)
    with open(labels_path) as f:
        labels = json.load(f)
    model = load_model(spec.model_path)
    res = classification(docs, labels, model, spec)
    out = {
        "task": spec.task_name,
        "model": MODEL_NAME,
        "run": run,
        "metric": "accuracy",
        "accuracy": res["accuracy"],
        "n": res["n"],
        "correct": res["correct"],
        "scored": res["scored"],
        "skipped": res["skipped"],
    }
    write_json(out_path, out)
    return out


def cmd_retrieval(spec_path, queries_path, out_path, run):
    spec = load_task_spec(spec_path)
    queries = read_lines(queries_path)
    res = retrieval(queries, spec)
    out = {
        "task": spec.task_name,
        "model": MODEL_NAME,
        "run": run,
        "scores": res["scores"],
        "metrics": res["metrics"],
        "n": res["n"],
    }
    write_json(out_path, out)
    return out


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "classify" and len(argv) >= 5:
        cmd_classify(argv[1], argv[2], argv[3], argv[4], DEFAULT_RUN)
    elif cmd == "retrieval" and len(argv) >= 4:
        cmd_retrieval(argv[1], argv[2], argv[3], DEFAULT_RUN)
    elif cmd == "describe":
        spec = load_task_spec(argv[1])
        print(json.dumps({
            "task": spec.task_name,
            "choices": spec.choices,
            "n_classes": spec.n_classes,
            "prompt": spec.prompt_template,
        }, indent=2))
    else:
        sys.stderr.write(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))