"""CLI entry point: python -m prismval --config C --data D --gold G --out O"""

import argparse
import json

from .engine import load_model, predict, tokenize
from .spec import load_spec


def main(argv=None):
    ap = argparse.ArgumentParser(prog="prismval")
    ap.add_argument("--config", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--gold", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    spec = load_spec(args.config)
    model = load_model(spec.model_path)

    docs = []
    with open(args.data, "r", encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                docs.append(json.loads(line))

    with open(args.gold, "r", encoding="utf-8") as fh:
        gold_raw = json.load(fh)
    labels = gold_raw["labels"]

    scored = []
    skipped = []
    for doc in docs:
        doc_id = str(doc.get("id"))
        text = doc.get(spec.text_column, "")
        spec.prompt_template.format(text=text)  # template must render
        tokens = tokenize(text)

        code = labels.get(doc_id)
        if (
            not isinstance(code, int)
            or isinstance(code, bool)
            or str(code) not in spec.gold_map
        ):
            skipped.append({"id": doc_id, "reason": "invalid-label"})
            continue
        idx = spec.gold_map[str(code)]
        if not isinstance(idx, int) or isinstance(idx, bool):
            skipped.append({"id": doc_id, "reason": "gold-out-of-range"})
            continue
        if not (0 <= idx < len(spec.choices)):
            skipped.append({"id": doc_id, "reason": "gold-out-of-range"})
            continue

        pred = predict(model, tokens)
        gold = spec.choices[idx]
        scored.append(
            {
                "id": doc_id,
                "pred": pred,
                "gold": gold,
                "pred_index": spec.choices.index(pred),
                "gold_index": idx,
                "correct": pred == gold,
            }
        )

    n = len(scored)
    correct = sum(1 for s in scored if s["correct"])
    result = {
        "task": spec.task_name,
        "metric": "accuracy",
        "accuracy": (correct / n) if n else 0.0,
        "n": n,
        "correct": correct,
        "scored": scored,
        "skipped": skipped,
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
