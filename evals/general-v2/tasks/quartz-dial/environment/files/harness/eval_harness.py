#!/usr/bin/env python3
"""Clean-room multi-choice logprobs evaluation harness (lm-eval style).

Reads a task configuration YAML authored by the agent and a JSONL of
evaluation rows, and:
  * reads the configured query / title / gold columns,
  * exposes the fixed choice label set,
  * builds each document's prompt from the mandated prompt template,
  * selects the gold label per document (doc_to_choice),
  * computes overall + per-label (macro) multiple-choice accuracy windows.

This module is generic: the only agent-authored artifact it interprets is
/app/tasks.yaml.  It is used both during the build (registration) and later by
the verifier on hidden query/title data.
"""
import argparse
import json
import sys
import yaml


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def load_task(yaml_path, task_name=None):
    with open(yaml_path, encoding="utf-8") as fh:
        raw = yaml.safe_load(fh)
    if not isinstance(raw, dict) or not raw:
        raise ValueError("tasks.yaml must be a non-empty mapping of task id -> config")
    if len(raw) != 1:
        # A single registered task is expected; if more, require an explicit name.
        if task_name is None:
            raise ValueError("multiple tasks in %s; pass --task-name" % yaml_path)
        name = task_name
    else:
        name = next(iter(raw))
    cfg = raw[name]
    conf = {
        "query_column": cfg.get("query_column", "query"),
        "title_column": cfg.get("title_column", "title"),
        "gold_column": cfg.get("gold_column", "gold"),
        "label_set": list(cfg["label_set"]),
        "prompt_template": cfg["prompt_template"],
        "metric": cfg.get("metric", "multiple_choice_accuracy"),
    }
    return name, conf


def build_prompt(tmpl, query, title, labels):
    options = "\n".join("- %s" % l for l in labels)
    return tmpl.format(query=query, title=title, options=options)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--predictions", default=None)
    ap.add_argument("--out", default="/app/eval_results.jsonl")
    ap.add_argument("--task-name", default=None)
    a = ap.parse_args()

    name, conf = load_task(a.task, a.task_name)
    label_set = conf["label_set"]
    rows = load_jsonl(a.data)

    preds = {}
    if a.predictions:
        for p in load_jsonl(a.predictions):
            preds[p.get("doc_id")] = p.get("scores")

    n_pred = 0
    per_label = {l: [0, 0] for l in label_set}  # [correct, total]
    per_doc = []
    for r in rows:
        gold_i = r[conf["gold_column"]]
        gold_label = label_set[gold_i]
        prompt = build_prompt(conf["prompt_template"],
                              r[conf["query_column"]],
                              r[conf["title_column"]],
                              label_set)
        chosen = gold_label
        if preds:
            scores = preds.get(r.get("doc_id"))
            if scores is not None:
                chosen = label_set[list(scores).index(max(scores))]
        correct = (chosen == gold_label)
        n_pred += int(correct)
        per_label[gold_label][1] += 1
        per_label[gold_label][0] += int(correct)
        per_doc.append({
            "doc_id": r.get("doc_id"),
            "gold_index": int(gold_i),
            "gold_label": gold_label,
            "chosen_label": chosen,
            "prompt": prompt,
            "prediction_scores": preds.get(r.get("doc_id")),
        })

    n = len(rows)
    overall = (n_pred / n) if n else 0.0
    pl = {l: (c[0] / c[1] if c[1] else 0.0) for l, c in per_label.items()}
    macro = sum(pl.values()) / len(pl) if pl else 0.0

    with open(a.out, "w", encoding="utf-8") as fh:
        for d in per_doc:
            fh.write(json.dumps(d, ensure_ascii=False) + "\n")
        fh.write(json.dumps({
            "task": name,
            "metric": conf["metric"],
            "overall_accuracy": overall,
            "macro_accuracy": macro,
            "per_label_accuracy": pl,
            "n_docs": n,
        }, ensure_ascii=False) + "\n")

    # Registration probe: print a loadable-task confirmation line.
    if n >= 0:
        print("task '%s' loaded (metric=%s, labels=%d docs=%d)"
              % (name, conf["metric"], len(label_set), n))


if __name__ == "__main__":
    main()