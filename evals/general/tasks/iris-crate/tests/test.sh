#!/bin/bash
# Verifier for iris-crate (executes-deliverable).
#
# Visible: EXECUTES /app/train.py on the shipped depot corpus, then scores the
#          freshly produced model AND the /app/model.bin deliverable on the
#          sealed holdout with the documented inference rule; enforces the
#          2 MiB size budget and metrics consistency; enforces the no-modify
#          rule on the provided inputs.
# Hidden : re-runs /app/train.py on two genuinely different corpora (a fresh
#          seed, and an edge corpus with malformed rows) and scores each
#          produced model on that corpus's holdout against its floor.
# Writes reward (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

# pristine shas of the provided inputs (no-modify rule)
PRISTINE_TRAIN_SHA="09e9a0068b7d8ac671561524e351ce727a2da920d8398f40f0a85c0281bab54b"
PRISTINE_HOLD_SHA="dfd51bf6686ca8ed02a356dcb442d3858954d740a299ffeed31192984a9a0b3a"

no_modify_broken=0
for pair in "/app/data/train.tsv:$PRISTINE_TRAIN_SHA" "/app/data/holdout.tsv:$PRISTINE_HOLD_SHA"; do
    f="${pair%%:*}"; want="${pair#*:}"
    if [ ! -f "$f" ]; then
        echo "no-modify: $f missing" >&2
        no_modify_broken=1
    else
        got="$(sha256sum "$f" | awk '{print $1}')"
        if [ "$got" != "$want" ]; then
            echo "no-modify: $f was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json
import os
import pickle
import re
import subprocess
import sys
import zlib

TRAIN = "/app/train.py"
NBUCKETS = 65536
TOKEN = re.compile(r"[a-z0-9]+")
DEFAULT_CAP = 2097152
VISIBLE_FLOOR = 0.88
no_modify_broken = int(sys.argv[1])

failures = []


def features(text):
    toks = TOKEN.findall(text.lower())
    grams = toks + [toks[i] + "\x1f" + toks[i + 1]
                    for i in range(len(toks) - 1)]
    return [zlib.crc32(g.encode("utf-8")) % NBUCKETS for g in grams]


def read_rows(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if "\t" not in line:
                    continue
                lab, _, txt = line.partition("\t")
                lab, txt = lab.strip(), txt.strip()
                if not lab or not txt:
                    continue
                rows.append((lab, txt))
    except OSError as e:
        failures.append("unreadable %s: %r" % (path, e))
    return rows


def load_model(path):
    try:
        with open(path, "rb") as fh:
            m = pickle.load(fh)
        assert isinstance(m, dict), "model is not a dict"
        assert set(m.keys()) == {"labels", "bias", "w"}, m.keys()
        labels = m["labels"]
        bias = m["bias"]
        w = m["w"]
        K = len(labels)
        assert isinstance(labels, list) and K >= 1
        assert all(isinstance(x, str) for x in labels)
        assert isinstance(bias, list) and len(bias) == K
        assert isinstance(w, dict)
        for f, wv in w.items():
            assert isinstance(f, int) and 0 <= f < NBUCKETS, f
            assert isinstance(wv, list) and len(wv) == K, f
        return m
    except Exception as e:
        failures.append("bad model %s: %r" % (path, e))
        return None


def score(m, rows):
    """Documented inference rule; returns accuracy on well-formed rows."""
    labels, bias, w = m["labels"], m["bias"], m["w"]
    K = len(labels)
    correct = total = 0
    for lab, txt in rows:
        F = features(txt)
        n = max(1, len(F))
        scores = bias[:]
        for f in F:
            wv = w.get(f)
            if wv is not None:
                for j in range(K):
                    scores[j] += wv[j] / n
        best = 0
        for j in range(1, K):
            if scores[j] > scores[best]:
                best = j
        total += 1
        if labels[best] == lab:
            correct += 1
    return (correct / total) if total else 0.0


def run_trainer(train_path, model_out, metrics_out):
    for p in (model_out, metrics_out):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run([sys.executable, TRAIN, train_path, model_out,
                            metrics_out],
                           capture_output=True, text=True, timeout=240)
    except Exception as e:
        failures.append("trainer crashed on %s: %r" % (train_path, e))
        return None
    if r.returncode != 0:
        failures.append("trainer exited %d on %s: %s"
                        % (r.returncode, train_path, r.stderr[-300:]))
        return None
    if not os.path.isfile(model_out):
        failures.append("trainer wrote no model for %s" % train_path)
        return None
    return model_out


def check_size(path, cap):
    size = os.path.getsize(path)
    if size > cap:
        failures.append("model %s: %d bytes > cap %d" % (path, size, cap))
    return size


def check_metrics(metrics_path, model_path):
    try:
        with open(metrics_path) as fh:
            rep = json.load(fh)
        assert isinstance(rep, dict)
        need = {"holdout_accuracy", "train_rows", "model_bytes", "labels"}
        assert need <= set(rep.keys()), rep.keys()
        acc = rep["holdout_accuracy"]
        assert isinstance(acc, (int, float)) and 0.0 <= acc <= 1.0, acc
        assert isinstance(rep["train_rows"], int) and rep["train_rows"] >= 0
        mb = rep["model_bytes"]
        assert isinstance(mb, int), mb
        actual = os.path.getsize(model_path)
        assert mb == actual, "model_bytes %d != actual %d" % (mb, actual)
        m = load_model(model_path)
        if m is not None:
            assert sorted(rep["labels"]) == sorted(m["labels"]), "labels mismatch"
    except Exception as e:
        failures.append("metrics %s bad: %r" % (metrics_path, e))


# ---------------------------------------------------------------- visible ---
if no_modify_broken:
    failures.append("provided inputs modified or missing (no-modify rule)")
if not os.path.isfile(TRAIN):
    failures.append("missing /app/train.py")
else:
    # execute the deliverable on the visible corpus
    out = run_trainer("/app/data/train.tsv",
                      "/tmp/iris_vis_model.bin", "/tmp/iris_vis_metrics.json")
    if out is not None:
        rows = read_rows("/app/data/holdout.tsv")
        m = load_model(out)
        if m is not None:
            check_size(out, DEFAULT_CAP)
            acc = score(m, rows)
            if acc < VISIBLE_FLOOR:
                failures.append("fresh visible model acc %.4f < %.2f"
                                % (acc, VISIBLE_FLOOR))
            check_metrics("/tmp/iris_vis_metrics.json", out)
        # the shipped deliverables must also hold up
        if not os.path.isfile("/app/model.bin"):
            failures.append("missing /app/model.bin")
        else:
            m2 = load_model("/app/model.bin")
            if m2 is not None:
                check_size("/app/model.bin", DEFAULT_CAP)
                acc2 = score(m2, rows)
                if acc2 < VISIBLE_FLOOR:
                    failures.append("/app/model.bin acc %.4f < %.2f"
                                    % (acc2, VISIBLE_FLOOR))
        if not os.path.isfile("/app/metrics.json"):
            failures.append("missing /app/metrics.json")
        elif os.path.isfile("/app/model.bin"):
            check_metrics("/app/metrics.json", "/app/model.bin")

# ----------------------------------------------------------------- hidden ---
hidden = "/tests/hidden"
if not os.path.isdir(hidden) or not any(os.scandir(hidden)):
    failures.append("no hidden cases")
else:
    for name in sorted(os.listdir(hidden)):
        base = os.path.join(hidden, name)
        cfg_p = os.path.join(base, "case.json")
        tr_p = os.path.join(base, "train.tsv")
        ho_p = os.path.join(base, "holdout.tsv")
        if not all(os.path.isfile(p) for p in (cfg_p, tr_p, ho_p)):
            failures.append("hidden '%s' incomplete" % name)
            continue
        try:
            with open(cfg_p) as fh:
                cfg = json.load(fh)
            floor = float(cfg["min_accuracy"])
            cap = int(cfg.get("size_cap_bytes", DEFAULT_CAP))
        except Exception as e:
            failures.append("hidden '%s': bad case.json: %r" % (name, e))
            continue
        out = run_trainer(tr_p, "/tmp/iris_case_model.bin",
                          "/tmp/iris_case_metrics.json")
        if out is None:
            continue
        m = load_model(out)
        if m is None:
            continue
        check_size(out, cap)
        rows = read_rows(ho_p)
        acc = score(m, rows)
        if acc < floor:
            failures.append("hidden '%s': acc %.4f < floor %.2f"
                            % (name, acc, floor))
        check_metrics("/tmp/iris_case_metrics.json", out)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
