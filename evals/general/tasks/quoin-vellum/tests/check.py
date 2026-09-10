#!/usr/bin/env python3
"""Verifier helper for quoin-vellum.

Executes the agent's deliverable (/app/train_topics.py) on every hidden corpus,
reloads the produced model through gensim's own format, and scores it on c_v
topical coherence and topic-word purity against the hidden corpus ground truth.
All hidden corpora must pass; the first failure is reported on stdout with a
readable reason, leading test.sh to write reward 0.

Specification of thresholds (measured with the reference solution on the three
shipped hidden corpora, plus a wide margin):
  - coherence >= 0.85   (reference achieves ~0.97-0.98; a degenerate or wrong-
                         topic-count model collapses to 0.3-0.7 on some corpus)
  - purity    >= 0.65   (reference achieves 1.0; over/fixed-splitting models
                         fall to 0.4-0.6 on at least one corpus)
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

from gensim.models import LdaModel
from gensim.models.coherencemodel import CoherenceModel
from gensim.models.word2vec import LineSentence

DELIVERABLE, HIDDEN = sys.argv[1], sys.argv[2]
HIDDEN_CASES = ["topics3", "topics4", "topics5"]
COH_THRESHOLD = 0.85
PUR_THRESHOLD = 0.65
TOP_WORDS = 10


def purity(model, gt_sets):
    """Mean fraction of each topic's top words from a single (distinct) cluster."""
    used = set()
    psum, n = 0.0, 0
    for i in range(model.num_topics):
        wi = set(w for w, _ in model.show_topic(i, TOP_WORDS))
        best = max(range(len(gt_sets)),
                   key=lambda g: (len(wi & gt_sets[g]) if g not in used else -1))
        if best in used:
            continue
        psum += len(wi & gt_sets[best]) / TOP_WORDS
        used.add(best)
        n += 1
    return (psum / n) if n else 0.0


def evaluate(case_dir, out_model):
    """Return (ok, message)."""
    keys = json.load(open(os.path.join(case_dir, "keys.json"), encoding="utf-8"))
    gt_sets = [set(t) for t in keys["topics"]]
    docs = [list(s) for s in LineSentence(os.path.join(case_dir, "docs.txt"))]

    # The deliverable must see the corpus the way the agent's visible corpus
    # looks on disk: a directory holding ONLY docs.txt. The hidden case dirs
    # carry the verifier's ground truth (keys.json) next to the corpus, so we
    # stage a sanitized copy that contains nothing but the input the generic
    # pipeline contract promises. A deliverable that peeks for an answer file
    # in the corpus directory gets nothing here.
    sandbox = tempfile.mkdtemp(prefix="qv_corpus_")
    try:
        shutil.copyfile(os.path.join(case_dir, "docs.txt"),
                        os.path.join(sandbox, "docs.txt"))
        proc = subprocess.run(
            [sys.executable, DELIVERABLE, sandbox, out_model],
            capture_output=True, text=True, timeout=900)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
    if proc.returncode != 0:
        return False, ("deliverable crashed for %s:\n%s%s"
                       % (os.path.basename(case_dir),
                          proc.stdout[-400:], proc.stderr[-800:]))

    try:
        model = LdaModel.load(out_model)
    except Exception as exc:  # noqa: BLE001 — surface the load failure
        return False, ("model file %s is not loadable through gensim (serialisation "
                       "assertion failed): %r" % (out_model, exc))
    if not isinstance(model, LdaModel):
        return False, "output %s is not a gensim LdaModel" % out_model

    num_topics = model.num_topics
    cv = CoherenceModel(model=model, texts=docs, coherence="c_v").get_coherence()
    pur = purity(model, gt_sets)
    msg = ("%s: K=%d coherence=%.3f purity=%.3f"
           % (os.path.basename(case_dir), num_topics, cv, pur))
    failures = []
    if cv < COH_THRESHOLD:
        failures.append("coherence %.3f < %.2f" % (cv, COH_THRESHOLD))
    if pur < PUR_THRESHOLD:
        failures.append("purity %.3f < %.2f" % (pur, PUR_THRESHOLD))
    if failures:
        return False, msg + "  -> " + "; ".join(failures)
    return True, msg


def main():
    all_ok = True
    for case in HIDDEN_CASES:
        case_dir = os.path.join(HIDDEN, case)
        out_model = "/tmp/qv_%s.model" % case
        ok, msg = evaluate(case_dir, out_model)
        print(("  ok: " if ok else "  FAIL: ") + msg)
        if not ok:
            all_ok = False
    if not all_ok:
        print("NOT ALL HIDDEN CORPORA PASSED")
        return 1
    print("ALL HIDDEN CORPORA PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
