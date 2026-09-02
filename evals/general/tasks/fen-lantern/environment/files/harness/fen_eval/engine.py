"""fen_eval micro harness engine.

Deterministic multiple-choice classification over pre-tokenised documents.
All semantics are fixed here so a downstream verifier can recompute every
number independently.

Model ("fen-scout"): a JSON file with keys

  "name"    -> model identifier string,
  "classes" -> ordered class names; internal class k is classes[k],
  "vocab"   -> {token: [w0, w1, ...]} additive weights, one weight per class.

Prediction: for a document's ``tokens`` list the score of class k is the sum
of ``vocab`` weights over the tokens (tokens missing from the vocab contribute
0).  The predicted choice index is the argmax over k with ties broken by the
LOWEST index.  A document with an empty or missing ``tokens`` list scores
all-zero and is therefore predicted index 0.

Gold labels are class-name strings (e.g. "bittern").  The task configuration
maps each gold label string onto a choice index through its ``doc_to_choice``
table; the harness itself never guesses the mapping.
"""

import json

try:
    import yaml
except Exception:  # pragma: no cover
    yaml = None


class TaskSpec:
    """A parsed task configuration (YAML)."""

    def __init__(self, data):
        if not isinstance(data, dict):
            raise ValueError("task config must be a mapping")
        self.task_name = str(data["task_name"])
        self.model_path = str(data["model_path"])
        self.choices = [str(c) for c in data["choices"]]
        dc = data["doc_to_choice"]
        if not isinstance(dc, dict):
            raise ValueError("doc_to_choice must map gold label -> choice index")
        self.doc_to_choice = {str(k): int(v) for k, v in dc.items()}
        self.prompt_template = str(data["prompt_template"])
        self.run_name = str(data.get("run_name", "baseline"))


def load_task_spec(path):
    if yaml is None:
        raise RuntimeError("PyYAML is not installed")
    with open(path, "r", encoding="utf-8") as fh:
        return TaskSpec(yaml.safe_load(fh))


def load_model(path):
    with open(path, "r", encoding="utf-8") as fh:
        model = json.load(fh)
    for key in ("name", "classes", "vocab"):
        if key not in model:
            raise ValueError("model file missing %r" % key)
    return model


def load_docs(path):
    docs = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                docs.append(json.loads(line))
    return docs


def load_labels(path):
    with open(path, "r", encoding="utf-8") as fh:
        raw = json.load(fh)
    return {str(k): v for k, v in raw.items()}


def render_prompt(template, doc):
    """Render the task's prompt template for one document.

    The template references the ``{note}`` field; anything else raises.
    """
    return template.format(note=str(doc.get("note", "")))


def predict(model, tokens, n_classes):
    """Return the predicted choice index for one token list."""
    vocab = model["vocab"]
    scores = [0.0] * n_classes
    for tok in tokens or []:
        w = vocab.get(str(tok))
        if w:
            for k in range(min(n_classes, len(w))):
                scores[k] += w[k]
    best = 0
    for k in range(1, n_classes):
        if scores[k] > scores[best]:
            best = k
    return best


def evaluate(model, docs, labels, choices, gold_map, task_name, run_name):
    """Score ``docs`` against ``labels`` and return the canonical result."""
    n_classes = len(choices)
    if n_classes != len(model["classes"]):
        raise ValueError(
            "choices length (%d) must match the model's class count (%d)"
            % (n_classes, len(model["classes"]))
        )
    scored, skipped = [], []
    for doc in docs:
        did = str(doc.get("id"))
        gold_label = labels.get(did)
        idx = None if gold_label is None else gold_map.get(str(gold_label))
        if idx is None:
            skipped.append({"id": did, "reason": "unmapped-label"})
            continue
        if not isinstance(idx, int) or idx < 0 or idx >= n_classes:
            skipped.append({"id": did, "reason": "label-out-of-range"})
            continue
        pred = predict(model, doc.get("tokens"), n_classes)
        scored.append({"id": did, "pred": pred, "gold": idx, "correct": pred == idx})
    n = len(scored)
    correct = sum(1 for s in scored if s["correct"])
    return {
        "task": task_name,
        "model": model["name"],
        "run": run_name,
        "metric": "accuracy",
        "accuracy": (correct / n) if n else 0.0,
        "n": n,
        "correct": correct,
        "scored": scored,
        "skipped": skipped,
    }
