#!/usr/bin/env python3
"""Independent granite-inlet verifier. Reads the agent's deliverables and
recomputes every metric from scratch using the shipped cd-nano model and the
source fixtures, so nothing trusts the agent's arithmetic. Exits 2 on failure.
"""
import json
import re
import os
import subprocess
import sys

ROOT = "/app"
MOUNT = "/tests/hidden"
MODEL_PATH = os.path.join(ROOT, "model", "cd_nano.json")
DATA = os.path.join(ROOT, "data")
TOK = None
FAILURES = []


def fail(msg):
    FAILURES.append(msg)


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        fail("cannot read %s: %s" % (path, e))
        return None


def read_lines(path):
    rows = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    rows.append(json.loads(line))
    except Exception as e:
        fail("cannot read jsonl %s: %s" % (path, e))
    return rows


def get_tokens():
    global TOK
    if TOK is None:
        m = load_json(MODEL_PATH)
        TOK = m.get("tokens", {}) if m else {}
    return TOK


def predict(words, n_classes=4):
    s = [0.0] * n_classes
    for w in words:
        v = get_tokens().get(w)
        if v:
            for k in range(n_classes):
                s[k] += v[k]
    best = 0
    for k in range(1, n_classes):
        if s[k] > s[best]:
            best = k
    return best


def doc_words(doc):
    # Documented contract: a document whose `words` is empty/missing is
    # predicted 0 (no tokenization fallback is applied).
    w = doc.get("words")
    if w is None:
        return []
    return [str(t) for t in w]


def ref_classify(docs, labels, n_classes=4):
    scored = []
    skipped = []
    correct = 0
    for d in docs:
        wid = d.get("id")
        lab = labels.get(wid)
        if lab is None or isinstance(lab, bool) or not isinstance(lab, int):
            skipped.append(wid)
            continue
        lab = int(lab)
        if lab < 0 or lab >= n_classes:
            skipped.append(wid)
            continue
        pred = predict(doc_words(d), n_classes)
        ok = pred == lab
        correct += 1 if ok else 0
        scored.append({"id": wid, "pred": pred, "gold": lab, "correct": ok})
    n = len(scored)
    return {"n": n, "correct": correct,
            "accuracy": (correct / n) if n else None,
            "skipped": sorted(skipped), "scored": scored}


def check_classify(job, result, docspath, labels):
    docs = read_lines(docspath)
    ref = ref_classify(docs, labels, 4)
    acc = result.get("accuracy")
    n = result.get("n")
    correct = result.get("correct")
    if n != ref["n"] or correct != ref["correct"]:
        fail("%s: n/expected got (%s,%s) ref (%s,%s)" %
             (job, n, correct, ref["n"], ref["correct"]))
    if abs((acc or 0) - (ref["accuracy"] or 0)) > 1e-6:
        fail("%s: accuracy got %s ref %s" % (job, acc, ref["accuracy"]))
    ref_by = {r["id"]: r["pred"] for r in ref["scored"]}
    for r in result.get("scored", []):
        if r["id"] in ref_by and r["pred"] != ref_by[r["id"]]:
            fail("%s: per-sample pred mismatch on %s" % (job, r["id"]))
    got_skip = sorted(s.get("id") for s in result.get("skipped", []))
    if got_skip != ref["skipped"]:
        fail("%s: skipped mismatch" % job)
    print("  %s ok accuracy=%.4f n=%d" % (job, (acc or 0), n or 0))


def ref_retrieval(queries):
    agg = {"recall@5": 0.0, "mrr": 0.0}
    n = len(queries)
    for q in queries:
        cand = [str(x) for x in q.get("candidates", [])]
        rel = [str(x) for x in q.get("relevant", [])]
        rec = (sum(1 for r in rel if r in cand[:5]) / len(rel)) if rel else 0.0
        mrr = 0.0
        for idx, c in enumerate(cand):
            if c in rel:
                mrr = 1.0 / (idx + 1)
                break
        agg["recall@5"] += rec
        agg["mrr"] += mrr
    if n:
        agg["recall@5"] /= n
        agg["mrr"] /= n
    return agg, n


def check_retrieval(job, result, queriespath):
    queries = read_lines(queriespath)
    ref_agg, n = ref_retrieval(queries)
    met = result.get("metrics", {})
    for k in ("recall@5", "mrr"):
        ref = round(ref_agg[k], 6) if n else None
        got = met.get(k)
        if got is None or ref is None:
            if got != ref:
                fail("%s: %s mismatch got %s ref %s" % (job, k, got, ref))
            continue
        if abs(got - ref) > 1e-3:
            fail("%s: %s mismatch got %s ref %s" % (job, k, got, ref))
    print("  %s metrics=%s" % (job, met))


def main():
    # contract content of tasks.yaml
    try:
        yaml_text = open(os.path.join(ROOT, "tasks.yaml")).read()
    except Exception as e:
        fail("cannot read tasks.yaml: %s" % e)
        yaml_text = ""
    for needle in ["caldera", "canyon", "delta", "estuary", "{title}", "{query}",
                   "doc_to_choice", "n_classes", "cd_nano"]:
        if needle not in yaml_text:
            fail("tasks.yaml missing %r" % needle)
    # Deliverable /app/register_tasks.py: must be runnable and re-register
    # cleanly (regenerating the registry manifest from tasks.yaml).
    # The instruction only requires the deliverable be runnable with
    # `python3 /app/register_tasks.py`; it need not carry the exec bit, so the
    # verifier must invoke it through the interpreter, not by execve.
    try:
        reg = subprocess.run([sys.executable, "/app/register_tasks.py"], capture_output=True, text=True)
    except OSError as e:
        reg = None
        fail("/app/register_tasks.py not found: %s" % e)
    if reg is not None:
        if reg.returncode != 0:
            fail("/app/register_tasks.py failed: %s" % (reg.stderr or reg.stdout).strip())
        if not os.path.exists("/app/tasks_registry.json"):
            fail("/app/register_tasks.py did not write tasks_registry.json")
    try:
        import granite_eval  # installed, importable harness package
    except Exception as e:
        fail("harness package not importable: %s" % e)

    # visible deliverables
    # Deliverable /app/results/channel_fathom/sprint_07.json (classification).
    cvis = "/app/results/channel_fathom/sprint_07.json"
    if not os.path.exists(cvis):
        fail("missing visible channel_fathom result")
    else:
        check_classify("visible/channel_fathom", load_json(cvis),
                       os.path.join(ROOT, "data", "channel_docs.jsonl"),
                       load_json(os.path.join(ROOT, "data", "channel_labels.json")))
    # Deliverable /app/results/aperture_map/sprint_07.json (retrieval).
    vret = "/app/results/aperture_map/sprint_07.json"
    if not os.path.exists(vret):
        fail("missing visible retrieval result")
    else:
        check_retrieval("visible/aperture_map", load_json(vret),
                        os.path.join(ROOT, "data", "queries.jsonl"))

    # hidden classification + retrieval (produced by run_eval in test.sh)
    for name in ["h1", "h2", "h3", "h4", "h5"]:
        rp = "/app/results/_verify%s.json" % name
        if not os.path.exists(rp):
            fail("hidden %s: run_eval produced no output" % name)
            continue
        res = load_json(rp)
        labels = load_json(os.path.join(MOUNT, name, "labels.json"))
        check_classify("hidden/%s" % name, res,
                       os.path.join(MOUNT, name, "docs.jsonl"), labels)
    for name in ["h6", "h7"]:
        rp = "/app/results/_verify_ret%s.json" % name
        if not os.path.exists(rp):
            fail("hidden %s: no retrieval output" % name)
            continue
        check_retrieval("hidden/%s" % name, load_json(rp),
                        os.path.join(MOUNT, name, "queries.jsonl"))

    if FAILURES:
        print("FAILURES:")
        for f in FAILURES:
            print("  - " + f)
        return 2
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())