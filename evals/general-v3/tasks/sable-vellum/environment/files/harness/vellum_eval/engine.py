"""vellum_eval micro eval harness engine.

Doc/choice/target task shape modelled on log-prob multiple-choice
benchmarking. All semantics are deterministic and documented so a downstream
verifier can recompute them independently.

Model ("vex-nano"): a tiny additive token-weight scorer. For each class k the
model table maps a token to a weight vector; a document's score for class k is
the sum of weight[t][k] over the document's tokens. The predicted class is the
argmax over classes, ties broken by the SMALLEST class index. A document with
no known tokens scores 0.0 in every class and is predicted class 0.
"""

import json

try:
    import yaml
except Exception:  # pragma: no cover
    yaml = None

import re

TOKEN_RE = re.compile(r"[a-z0-9]+")


class TaskSpec:
    """A parsed task configuration (YAML)."""

    def __init__(self, data):
        self.data = data
        self.task_name = str(data["task_name"])
        self.n_classes = int(data["n_classes"])
        self.choices = [str(c) for c in data["choices"]]
        self.model_path = str(data["model_path"])
        self.prompt_template = str(data.get("prompt_template", ""))
        self.query_column = str(data.get("query_column", "excerpt"))
        self.title_column = str(data.get("title_column", "title"))
        self.doc_to_choice = str(data.get("doc_to_choice", "label"))


def load_task_spec(path):
    if yaml is None:
        raise RuntimeError("PyYAML not installed")
    with open(path, "r", encoding="utf-8") as f:
        return TaskSpec(yaml.safe_load(f))


def load_model(path):
    """Model JSON: {"name": ..., "tokens": {token: [w0 .. w(n-1)]}}."""
    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f)
    if isinstance(raw, dict) and "tokens" in raw:
        return raw
    return {"tokens": raw}


def tokenize(text):
    """Lowercase, then extract [a-z0-9]+ word tokens in order."""
    return TOKEN_RE.findall((text or "").lower())


def doc_text(doc, spec):
    t = str(doc.get(spec.title_column, "") or "")
    q = str(doc.get(spec.query_column, "") or "")
    return f"{t}\n{q}"


def predict(model, text, n_classes):
    table = model.get("tokens", {})
    scores = [0.0] * n_classes
    for tok in tokenize(text):
        vec = table.get(tok)
        if vec:
            for k in range(min(n_classes, len(vec))):
                scores[k] += float(vec[k])
    best = 0
    for k in range(1, n_classes):
        if scores[k] > scores[best]:  # strict: ties keep the smallest index
            best = k
    return best


def render_prompt(spec, doc):
    """Render the task's prompt template for one document."""
    t = str(doc.get(spec.title_column, "") or "")
    q = str(doc.get(spec.query_column, "") or "")
    try:
        return spec.prompt_template.format(title=t, excerpt=q)
    except (KeyError, IndexError):
        return doc_text(doc, spec)


def classification(docs, labels, model, spec):
    """Score every document against gold labels.

    Gold labels map doc id -> a choice LABEL (one of spec.choices, e.g.
    "herb"). The gold class index is the label's position in spec.choices, so
    the declared choice order is part of the contract. A document is SCORED
    only when labels[id] exists and is a string equal to one of the declared
    choice labels; anything else is SKIPPED with reason "invalid-label" and
    excluded from n and accuracy. Empty/missing text documents are still
    scored (they are predicted class 0).
    """
    n_classes = spec.n_classes
    scored = []
    skipped = []
    correct = 0
    for d in docs:
        wid = d.get("id")
        if wid is None:
            continue
        lab = labels.get(wid)
        if not isinstance(lab, str) or lab not in spec.choices:
            skipped.append({"id": wid, "reason": "invalid-label"})
            continue
        gold = spec.choices.index(lab)
        pred = predict(model, doc_text(d, spec), n_classes)
        ok = (pred == gold)
        if ok:
            correct += 1
        scored.append({"id": wid, "pred": pred, "gold": gold, "correct": ok})
    n = len(scored)
    accuracy = (correct / n) if n else None
    return {
        "task": spec.task_name,
        "n": n,
        "correct": correct,
        "accuracy": accuracy,
        "scored": scored,
        "skipped": skipped,
    }
