#!/bin/bash
# Verifier for cobalt-sonar: checks the visible deliverables, then EXECUTES
# /app/train.py on the visible corpus and on every hidden corpus in
# /tests/hidden, applying the accuracy bar, the serialized-size budget, and
# report-honesty checks to each run. Writes REWARD to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
trap '[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt' EXIT

python3 - <<'PY'
import hashlib, json, os, subprocess, sys, tempfile

TRAINER = "/app/train.py"
SIZE_BUDGET = 120000
ACC_MIN = 0.91
LABELS = ("billing", "outage", "feature")

failures = []


def read_rows(path):
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                continue
            label, text = parts[0].strip(), parts[1].strip()
            if label not in LABELS or not text:
                continue
            rows.append((label, text))
    return rows


def is_test(text):
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest(), 16) % 5 == 0


def check_run(corpus, outdir, tag):
    """Run the trainer and apply every gate to its artifacts."""
    if os.path.isdir(outdir):
        import shutil
        shutil.rmtree(outdir)
    proc = subprocess.run(
        [sys.executable, TRAINER, corpus, outdir],
        capture_output=True, text=True, timeout=240,
    )
    if proc.returncode != 0:
        failures.append("%s: trainer exited %d: %s" % (tag, proc.returncode, proc.stderr[-300:]))
        return
    model_path = os.path.join(outdir, "model.bin")
    report_path = os.path.join(outdir, "report.json")
    if not os.path.isfile(model_path):
        failures.append("%s: missing model.bin" % tag)
        return
    if not os.path.isfile(report_path):
        failures.append("%s: missing report.json" % tag)
        return

    # size gate
    mbytes = os.path.getsize(model_path)
    if mbytes > SIZE_BUDGET:
        failures.append("%s: model.bin %d > %d bytes" % (tag, mbytes, SIZE_BUDGET))

    # report honesty
    try:
        with open(report_path) as fh:
            rep = json.load(fh)
        assert isinstance(rep, dict), "not a dict"
        assert set(rep.keys()) == {
            "corpus_path", "total_rows", "train_rows", "test_rows",
            "model_bytes", "holdout_accuracy",
        }, "keys %s" % sorted(rep.keys())
        assert rep["corpus_path"] == corpus, "corpus_path %r" % rep["corpus_path"]
        for k in ("total_rows", "train_rows", "test_rows", "model_bytes"):
            assert isinstance(rep[k], int), "%s not int" % k
        assert isinstance(rep["holdout_accuracy"], float) or isinstance(rep["holdout_accuracy"], int)
    except Exception as e:
        failures.append("%s: bad report.json (%s)" % (tag, e))
        return

    rows = read_rows(corpus)
    train = [t for _, t in rows if not is_test(t)]
    test = [(l, t) for l, t in rows if is_test(t)]
    if rep["total_rows"] != len(rows):
        failures.append("%s: total_rows %d != %d" % (tag, rep["total_rows"], len(rows)))
    if rep["train_rows"] != len(train):
        failures.append("%s: train_rows %d != %d" % (tag, rep["train_rows"], len(train)))
    if rep["test_rows"] != len(test):
        failures.append("%s: test_rows %d != %d" % (tag, rep["test_rows"], len(test)))
    if rep["model_bytes"] != mbytes:
        failures.append("%s: model_bytes %d != %d" % (tag, rep["model_bytes"], mbytes))

    # accuracy gate: reload the saved model and recompute holdout accuracy
    if not test:
        failures.append("%s: empty test split" % tag)
        return
    try:
        import fasttext
        model = fasttext.load_model(model_path)
        correct = 0
        for label, text in test:
            if model.predict(text)[0][0] == "__label__" + label:
                correct += 1
        acc = correct / len(test)
    except Exception as e:
        failures.append("%s: could not evaluate saved model (%s)" % (tag, e))
        return
    print("%s: model_bytes=%d holdout_accuracy=%.4f" % (tag, mbytes, acc))
    if acc < ACC_MIN:
        failures.append("%s: holdout accuracy %.4f < %.2f" % (tag, acc, ACC_MIN))
    if abs(float(rep["holdout_accuracy"]) - acc) > 0.005:
        failures.append("%s: reported accuracy %s != recomputed %.4f"
                        % (tag, rep["holdout_accuracy"], acc))


# ------------------------------------------------------------- deliverables ---
for p in (TRAINER, "/app/model.bin", "/app/report.json"):
    if not os.path.isfile(p):
        failures.append("missing deliverable %s" % p)

if not failures:
    # ---------------------------------------------------- visible corpus run ---
    if not os.path.isfile("/app/data/tickets.tsv"):
        failures.append("missing /app/data/tickets.tsv")
    else:
        check_run("/app/data/tickets.tsv", "/tmp/sonar_visible_out", "visible")

    # ------------------------------------------------------- hidden corpora ---
    hid = "/tests/hidden"
    if os.path.isdir(hid):
        cases = sorted(d for d in os.listdir(hid) if os.path.isdir(os.path.join(hid, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            corpus = os.path.join(hid, c, "tickets.tsv")
            if not os.path.isfile(corpus):
                failures.append("hidden '%s': missing tickets.tsv" % c)
                continue
            check_run(corpus, "/tmp/sonar_hidden_out_%s" % c, "hidden:%s" % c)
    else:
        failures.append("no /tests/hidden directory")

print("verify failures:", failures)
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1" if not failures else "0")
sys.exit(0)
PY
