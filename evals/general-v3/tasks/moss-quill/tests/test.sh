#!/bin/bash
# Verifier for moss-quill (executes-deliverable).
#
# Visible: executes /app/train.py on the shipped /app/data/tickets.tsv into a
#          temp dir, evaluates the produced model on the documented
#          deterministic holdout (accuracy floor + size budget + report
#          integrity), and additionally evaluates the agent's shipped
#          /app/model.pkl and /app/report.json on the same holdout. Guards
#          the no-modify rule on the supplied corpus and generator.
# Hidden : re-runs the deliverable trainer on two genuinely different corpora
#          (a fresh domain mix, and an edge corpus with malformed rows), each
#          with its own accuracy floor, and re-checks everything.
#
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

PRISTINE_CORPUS_SHA="$(sha256sum /app/data/tickets.tsv 2>/dev/null | awk '{print $1}')"
EXPECTED_CORPUS_SHA="fcb5089ed4730c1d4426552110f927237c37fcb2da3eb1c2f74b61ad383e2613"

python3 - "$PRISTINE_CORPUS_SHA" "$EXPECTED_CORPUS_SHA" <<'PY'
import hashlib
import json
import os
import pickle
import subprocess
import sys

pristine_sha, expected_sha = sys.argv[1], sys.argv[2]
TRAIN = "/app/train.py"
failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg)


def read_corpus(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line.strip() or "\t" not in line:
                    continue
                lab, _, txt = line.partition("\t")
                lab, txt = lab.strip(), txt.strip()
                if not lab or not txt:
                    continue
                rows.append((lab, txt))
    except Exception as e:
        fail("unreadable corpus %s: %s" % (path, e))
        return []
    return rows


def holdout(rows):
    train, test = [], []
    for lab, txt in rows:
        h = int(hashlib.sha256(txt.encode("utf-8")).hexdigest(), 16)
        (test if h % 5 == 0 else train).append((lab, txt))
    return train, test


def check_model(model_path, report_path, corpus, min_acc, budget):
    """Load a trained model + report and verify every contract clause."""
    rows = read_corpus(corpus)
    if not rows:
        return False
    train, test = holdout(rows)
    truth = [l for l, _ in test]

    # ---- size budget (raw bytes on disk)
    try:
        size = os.path.getsize(model_path)
    except Exception as e:
        fail("missing/unreadable model %s: %s" % (model_path, e))
        return False
    if size > budget:
        fail("model size %d exceeds budget %d" % (size, budget))

    # ---- genuine holdout accuracy via .predict on raw text
    try:
        with open(model_path, "rb") as fh:
            clf = pickle.load(fh)
    except Exception as e:
        fail("unpicklable model %s: %s" % (model_path, e))
        return False
    try:
        pred = clf.predict([t for _, t in test])
        pred = [str(p) for p in pred]
        assert len(pred) == len(truth), "predict returned wrong arity"
    except Exception as e:
        fail("model.predict failed on %s: %s" % (model_path, e))
        return False
    acc = sum(p == l for p, l in zip(pred, truth)) / len(truth) if truth else 0.0
    if acc < min_acc:
        fail("holdout accuracy %.4f below floor %.4f (%s)" % (acc, min_acc, corpus))

    # ---- report integrity
    try:
        with open(report_path) as fh:
            rep = json.load(fh)
        assert isinstance(rep, dict), "report not a dict"
        assert set(rep.keys()) == {"train_rows", "test_rows", "holdout_accuracy",
                                   "model_bytes", "budget_bytes", "labels"}, rep.keys()
        assert rep["train_rows"] == len(train), (rep["train_rows"], len(train))
        assert rep["test_rows"] == len(test), (rep["test_rows"], len(test))
        assert abs(float(rep["holdout_accuracy"]) - acc) <= 0.02, \
            (rep["holdout_accuracy"], acc)
        assert rep["model_bytes"] == size, (rep["model_bytes"], size)
        assert rep["budget_bytes"] == 262144, rep["budget_bytes"]
        assert rep["labels"] == sorted({l for l, _ in rows}), rep["labels"]
    except AssertionError as e:
        fail("report integrity on %s: %s" % (report_path, e))
    except Exception as e:
        fail("unreadable/invalid report %s: %s" % (report_path, e))
    return True


def run_trainer(corpus, workdir):
    """Execute the deliverable trainer on a corpus; returns (model, report)."""
    os.makedirs(workdir, exist_ok=True)
    model = os.path.join(workdir, "model.pkl")
    report = os.path.join(workdir, "report.json")
    try:
        r = subprocess.run([sys.executable, TRAIN, corpus, model, report],
                           capture_output=True, text=True, timeout=240)
    except Exception as e:
        fail("execute trainer on %s: %s" % (corpus, e))
        return None, None
    if r.returncode != 0:
        fail("trainer exited %d on %s: %s" % (r.returncode, corpus, r.stderr[-300:]))
        return None, None
    return model, report


# ---------------- no-modify guard on supplied fixtures ----------------
if not os.path.isfile("/app/data/tickets.tsv"):
    fail("/app/data/tickets.tsv missing")
elif pristine_sha != expected_sha:
    fail("/app/data/tickets.tsv was modified")
if not os.path.isfile("/app/gen_tickets.py"):
    fail("/app/gen_tickets.py missing")

# ---------------- visible corpus: execute the trainer ----------------
if not os.path.isfile(TRAIN):
    fail("missing /app/train.py")
else:
    m, rep = run_trainer("/app/data/tickets.tsv", "/tmp/mq_vis")
    if m:
        check_model(m, rep, "/app/data/tickets.tsv", 0.91, 262144)

    # shipped visible-case deliverables must exist and hold on the same split
    if not os.path.isfile("/app/model.pkl"):
        fail("missing /app/model.pkl")
    else:
        check_model("/app/model.pkl", "/app/report.json",
                    "/app/data/tickets.tsv", 0.91, 262144)

    # ---------------- hidden corpora ----------------
    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        fail("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        corpus = os.path.join(base, "corpus.tsv")
        meta_p = os.path.join(base, "meta.json")
        if not (os.path.isfile(corpus) and os.path.isfile(meta_p)):
            fail("hidden case '%s' malformed" % c)
            continue
        try:
            meta = json.load(open(meta_p))
            min_acc = float(meta["min_accuracy"])
            budget = int(meta["budget_bytes"])
        except Exception as e:
            fail("hidden case '%s' meta unreadable: %s" % (c, e))
            continue
        m, rep = run_trainer(corpus, "/tmp/mq_hidden_%s" % c)
        if m:
            before = len(failures)
            check_model(m, rep, corpus, min_acc, budget)
            if len(failures) > before:
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
