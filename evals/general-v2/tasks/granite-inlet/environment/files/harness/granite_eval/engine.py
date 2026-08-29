"""granite-inlet micro eval harness engine.

The harness exposes a doc/choice/target task shape modelled on log-prob
multiple-choice benchmarking. All model semantics are deterministic and
documented so a downstream verifier can recompute them independently.

Model ("cd-nano"): a zero-parameter Naive-Bayes-like scorer. For each class k a
token contributes an additive weight; the predicted class is argmax_k of the
summed weights over the document's token list, ties broken by the lowest index.
"""

import json
import re

try:
    import yaml
except Exception:  # pragma: no cover
    yaml = None


class TaskSpec:
    """A parsed task configuration."""

    def __init__(self, data):
        self.data = data
        self.task_name = data["task_name"]
        self.n_classes = int(data.get("n_classes", 4))
        self.choices = [str(c) for c in data.get("choices", [])]
        self.model_path = data["model_path"]
        self.prompt_template = data.get("prompt_template", "")
        self.query_column = data.get("query_column", "query")
        self.title_column = data.get("title_column", "title")
        self.doc_to_choice = data.get("doc_to_choice", "label")

    def doc_text(self, doc):
        q = str(doc.get(self.query_column, ""))
        t = str(doc.get(self.title_column, ""))
        return f"{t}\n{q}"


def load_task_spec(path):
    if yaml is None:
        raise RuntimeError("PyYAML not installed")
    with open(path) as f:
        return TaskSpec(yaml.safe_load(f))


def load_model(path):
    """coo model JSON: {"tokens": {token: [w0..w(n-1)]}, ...}."""
    with open(path) as f:
        raw = json.load(f)
    if isinstance(raw, dict) and "tokens" in raw:
        return raw
    return {"tokens": raw}


def tokenize(text):
    return re_findall(text)


def re_findall(text):
    import re
    return re.findall(r"[a-z0-9]+", (text or "").lower())


def doc_words(doc, spec):
    # Documented contract: a document whose `words` is empty/missing is
    # predicted 0 (no tokenization fallback is applied).
    w = doc.get("words")
    if w is None:
        return []
    return [str(t) for t in w]


def predict(model, words, n_classes):
    table = model.get("tokens", {})
    s = [0.0] * n_classes
    for w in words:
        v = table.get(w)
        if v:
            for k in range(n_classes):
                s[k] += v[k]
    best = 0
    for k in range(1, n_classes):
        if s[k] > s[best]:
            best = k
    return best


def render_prompt(spec, doc):
    """Render the mandated prompt template for a document."""
    if not spec.prompt_template:
        return spec.doc_text(doc)
    q = str(doc.get(spec.query_column, ""))
    t = str(doc.get(spec.title_column, ""))
    try:
        return spec.prompt_template.format(query=q, title=t)
    except KeyError:
        return spec.doc_text(doc)


def classification(docs, labels, model, spec):
    """Score every document. Skipped = invalid label, excluded from n/accuracy.

    Returns a dict with canonical keys n, correct, accuracy, scored, skipped.
    """
    n_classes = spec.n_classes
    scored = []
    skipped = []
    correct = 0
    seen = set()
    for d in docs:
        wid = d.get("id")
        if wid is None:
            continue
        seen.add(wid)
        lab = labels.get(wid)
        if lab is None or isinstance(lab, bool) or not isinstance(lab, int):
            skipped.append({"id": wid, "reason": "invalid-label"})
            continue
        lab = int(lab)
        if lab < 0 or lab >= n_classes:
            skipped.append({"id": wid, "reason": "label-out-of-range"})
            continue
        pred = predict(model, doc_words(d, spec), n_classes)
        ok = (pred == lab)
        if ok:
            correct += 1
        scored.append({"id": wid, "pred": pred, "gold": lab, "correct": ok})
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


def _recall_at(k, candidates, relevant):
    top = set(candidates[:k])
    if not relevant:
        return 0.0
    hits = sum(1 for r in relevant if r in top)
    return hits / len(relevant)


def _mrr(candidates, relevant):
    rel = set(relevant)
    for idx, cid in enumerate(candidates):
        if cid in rel:
            return 1.0 / (idx + 1)
    return 0.0


def retrieval(queries, spec=None, k=5):
    """Per-query recall@k + MRR semantics for the retrieval benchmark."""
    rows = []
    for q in queries:
        cands = [str(x) for x in q.get("candidates", [])]
        rel = [str(x) for x in q.get("relevant", [])]
        rows.append({
            "query": q.get("id"),
            "recall@%d" % k: _recall_at(k, cands, rel),
            "mrr": _mrr(cands, rel),
        })
    qn = len(rows)
    rk = "recall@%d" % k
    def avg(key):
        return (sum(r[key] for r in rows) / qn) if qn else None
    return {
        "task": spec.task_name if spec else "retrieval",
        "n": qn,
        "scores": rows,
        "metrics": {
            rk: avg(rk),
            "mrr": avg("mrr"),
        },
    }