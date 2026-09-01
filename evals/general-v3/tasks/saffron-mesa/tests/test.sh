#!/bin/bash
# Verifier for saffron-mesa: reloads the persisted pickle deliverable and
# validates it against a reference fitted from the visible corpus, then
# EXECUTES the deliverable /app/fit.py on hidden corpora and validates each
# persisted pickle the same way. Writes 1/0 to /logs/verifier/reward.txt.
# Never crashes on malformed/missing agent output.
set -u

mkdir -p /logs/verifier
REWARD=0

python3 - <<'PY' && REWARD=1
import math
import os
import pickle
import re
import subprocess
import sys

FIT = "/app/fit.py"
failures = []


def tokenize(text):
    return re.findall(r"[a-z0-9]+", text.lower())


def reference(corpus_path):
    import csv
    docs = []
    with open(corpus_path, "r", encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh):
            docs.append((row["text"], row["label"]))
    n = len(docs)
    classes = sorted(set(label for _, label in docs))
    vocab = sorted(set(t for text, _ in docs for t in tokenize(text)))
    counts = {c: {} for c in classes}
    totals = {c: 0 for c in classes}
    doc_counts = {c: 0 for c in classes}
    for text, label in docs:
        doc_counts[label] += 1
        for t in tokenize(text):
            counts[label][t] = counts[label].get(t, 0) + 1
            totals[label] += 1
    log_prior = {c: math.log(doc_counts[c] / n) for c in classes}
    log_likelihood = {
        c: {t: math.log((counts[c].get(t, 0) + 1.0) / (totals[c] + len(vocab)))
            for t in vocab}
        for c in classes
    }
    return classes, vocab, log_prior, log_likelihood


def check_pickle(pkl_path, corpus_path, tag):
    if not os.path.isfile(pkl_path):
        failures.append("%s: pickle missing" % tag)
        return
    if os.path.getsize(pkl_path) == 0:
        failures.append("%s: pickle file empty" % tag)
        return
    try:
        with open(pkl_path, "rb") as fh:
            m = pickle.load(fh)
    except Exception as e:
        failures.append("%s: pickle not reloadable: %s" % (tag, e))
        return
    if not isinstance(m, dict) or set(m.keys()) != {
            "model_type", "alpha", "classes", "vocab",
            "log_prior", "log_likelihood"}:
        failures.append("%s: bad dict keys: %r" % (tag, sorted(m) if isinstance(m, dict) else m))
        return
    if m["model_type"] != "multinomial_nb" or m["alpha"] != 1.0:
        failures.append("%s: wrong model_type/alpha" % tag)
        return
    classes, vocab, log_prior, log_likelihood = reference(corpus_path)
    if m["classes"] != classes:
        failures.append("%s: classes mismatch %r != %r" % (tag, m["classes"], classes))
        return
    if m["vocab"] != vocab:
        failures.append("%s: vocab mismatch (%d vs %d tokens)" % (tag, len(m["vocab"]), len(vocab)))
        return
    try:
        for c in classes:
            if abs(m["log_prior"][c] - log_prior[c]) > 1e-9:
                failures.append("%s: log_prior[%s] mismatch" % (tag, c))
                return
            got = m["log_likelihood"][c]
            if set(got.keys()) != set(vocab):
                failures.append("%s: log_likelihood[%s] token keys wrong" % (tag, c))
                return
            for t in vocab:
                if abs(got[t] - log_likelihood[c][t]) > 1e-9:
                    failures.append("%s: log_likelihood[%s][%s] mismatch" % (tag, c, t))
                    return
    except Exception as e:
        failures.append("%s: numeric comparison failed: %s" % (tag, e))
        return


if not os.path.isfile(FIT):
    failures.append("missing /app/fit.py")
else:
    # visible persisted deliverable
    check_pickle("/app/model_store/nb_model.pkl", "/app/data/tickets.csv", "visible")

    # hidden generalization cases: re-run the deliverable, then validate
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(d for d in os.listdir(hidden)
                       if os.path.isdir(os.path.join(hidden, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            corpus = os.path.join(hidden, c, "tickets.csv")
            if not os.path.isfile(corpus):
                failures.append("hidden case %s malformed" % c)
                continue
            out = "/tmp/smesa_%s.pkl" % c
            if os.path.exists(out):
                os.remove(out)
            try:
                r = subprocess.run([sys.executable, FIT, corpus, out],
                                   capture_output=True, text=True, timeout=120)
            except Exception as e:
                failures.append("hidden %s crashed: %s" % (c, e))
                continue
            if r.returncode != 0:
                failures.append("hidden %s non-zero exit: %s" % (c, r.stderr[-300:]))
                continue
            check_pickle(out, corpus, "hidden-%s" % c)
    else:
        failures.append("no hidden case dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

echo "$REWARD" > /logs/verifier/reward.txt
exit 0
