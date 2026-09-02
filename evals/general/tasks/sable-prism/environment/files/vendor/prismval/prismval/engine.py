"""Deterministic lexicon scorer for prismval."""

import json
import re

TOKEN_RE = re.compile(r"[a-z0-9']+")


def tokenize(text):
    """Lowercase and keep [a-z0-9']+ runs."""
    return TOKEN_RE.findall(str(text).lower())


def load_model(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def class_scores(model, tokens):
    """Return {class_name: score}.  score_k = bias[k] + sum weights[tok][k]."""
    classes = model["classes"]
    bias = model["bias"]
    weights = model["weights"]
    scores = [float(b) for b in bias]
    for tok in tokens:
        w = weights.get(tok)
        if w:
            for k in range(len(classes)):
                scores[k] += float(w[k])
    return dict(zip(classes, scores))


def predict(model, tokens):
    """Argmax class name; ties broken by first-in-model["classes"] order."""
    classes = model["classes"]
    scores = class_scores(model, tokens)
    best = 0
    for k in range(1, len(classes)):
        if scores[classes[k]] > scores[classes[best]]:
            best = k
    return classes[best]
