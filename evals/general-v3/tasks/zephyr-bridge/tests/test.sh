#!/usr/bin/env bash
# zephyr-bridge verifier (executes-deliverable).
#
# Visible: loads/executes every /app artifact and the loader contract.
# Hidden : runs the deliverable runner `bash /app/run.sh <corpus> <outdir>` on
#          two genuinely different synthetic corpora (a fresh domain, and an
#          edge corpus with malformed/blank/duplicate rows) and re-checks the
#          produced files with the same loader.
#
# Reward (0..1): 0.5 visible + 0.25 per hidden scenario = 1.0.
set -uo pipefail
mkdir -p /logs/verifier
trap 'test -f /logs/verifier/reward.txt || echo "0.0000" > /logs/verifier/reward.txt' EXIT
cd /app

python3 - <<'PY'
import json, os, pickle, subprocess, sys
sys.path.insert(0, "/app")
import numpy as np
import zeph_loader as L

HID = "/tests/hidden"
BUDGET_BYTES = 8 * 1024 * 1024
EMB_DIM = 300

reward = 0.0
failmsgs = []

def fail(msg):
    failmsgs.append(msg)
    print("FAIL:", msg)

# ---------------------------------------------------------------- visible ---
# Explicitly execute/load each declared /app deliverable (literal paths).
existing_missing = []
for _d in ["/app/run.sh", "/app/vocab.txt", "/app/merges.txt",
           "/app/embeddings.npy", "/app/metrics.csv",
           "/app/vocab.pkl", "/app/model.pkl"]:
    if not os.path.exists(_d):
        existing_missing.append(_d)
if existing_missing:
    fail("VISIBLE deliverable missing: " + ",".join(existing_missing))


def parse_metrics(path):
    rows = []
    with open(path) as fh:
        header = fh.readline().rstrip("\n")
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            rows.append(line)
    return header, rows

def chain_ok(merges):
    units = set()
    for a, b in merges:
        if not (a in units or len(a) == 1):
            return False
        if not (b in units or len(b) == 1):
            return False
        units.add(a + b)
    return True

def structure_ok(outdir, corpus):
    """Structural + alignment + model-load + accuracy checks for an outdir."""
    local = []
    try:
        # vocab.txt
        vt = L.load_vocab(os.path.join(outdir, "vocab.txt"))
        if not vt:
            local.append("vocab.txt empty")
        # embeddings
        E = np.load(os.path.join(outdir, "embeddings.npy"))
        if E.ndim != 2 or E.shape[1] != EMB_DIM:
            local.append("embeddings shape %r != (V,%d)" % (E.shape, EMB_DIM))
        if len(vt) != E.shape[0]:
            local.append("vocab(%d) != embedding rows(%d)" % (len(vt), E.shape[0]))
        # vocab.pkl dataclass
        v = pickle.load(open(os.path.join(outdir, "vocab.pkl"), "rb"))
        if not isinstance(v, L.Vocab):
            local.append("vocab.pkl not a Vocab dataclass")
        if v.size() != len(vt):
            local.append("vocab.pkl size %d != vocab.txt %d" % (v.size(), len(vt)))
        if v.size() != E.shape[0]:
            local.append("vocab.pkl size %d != embedding rows %d" % (v.size(), E.shape[0]))
        if not v.check_inverse():
            local.append("vocab.pkl maps are not exact inverses")
        if set(vt) != set(v.word2idx):
            local.append("vocab.pkl tokens != vocab.txt tokens")
        # merges
        merge_rows = L.load_merges(os.path.join(outdir, "merges.txt"))
        if len(merge_rows) < 200:
            local.append("too few merge rules (%d)" % len(merge_rows))
        if not chain_ok(merge_rows):
            local.append("merge rules are not a consistent BPE chain")
        # metrics
        header, mrows = parse_metrics(os.path.join(outdir, "metrics.csv"))
        if header != "model,correlation,error,penalty,dof":
            local.append("metrics header %r" % header)
        models = set()
        if len(mrows) != 3:
            local.append("metrics rows=%d != 3" % len(mrows))
        for line in mrows:
            p = line.split(",")
            if len(p) != 5:
                local.append("metrics bad row %r" % line); continue
            name, corr, err, pen, dof = p[0], float(p[1]), float(p[2]), float(p[3]), p[4]
            models.add(name)
            if not (0.0 <= corr <= 1.0):
                local.append("metrics corr %s out of range" % corr)
            if not (0.0 <= err <= 1.0):
                local.append("metrics err %s out of range" % err)
            if not (0.0 <= pen <= 1.0):
                local.append("metrics penalty %s out of range" % pen)
            if abs((1.0 - corr) - err) > 0.05:
                local.append("metrics corr/err inconsistent for %s" % name)
            if not (dof.strip().isdigit() and int(dof) >= 1):
                local.append("metrics dof %r not a positive int" % dof)
        if models != {"pmi", "cbow", "skipgram"}:
            local.append("metrics model set %r" % sorted(models))
        # model.pkl (fasttext-style linear on mean embeddings)
        M = pickle.load(open(os.path.join(outdir, "model.pkl"), "rb"))
        if "clf" not in M or "classes" not in M:
            local.append("model.pkl missing clf/classes keys")
        clf, classes = M["clf"], M["classes"]
        if not hasattr(clf, "predict") or not hasattr(clf, "coef_"):
            local.append("model.pkl clf is not a linear classifier")
        elif clf.coef_.shape[1] != EMB_DIM:
            local.append("clf coef width %d != %d" % (clf.coef_.shape[1], EMB_DIM))
        size = os.path.getsize(os.path.join(outdir, "model.pkl"))
        if size > BUDGET_BYTES:
            local.append("model.pkl %d bytes > budget" % size)
        # accuracy on the loader's deterministic holdout
        rows = L.read_corpus(corpus)
        tr, te = L.split_corpus(rows)
        X = L.vectorize([t for _, t in te], v, E)
        # The instruction contract is "classes: [sorted label names]", so a
        # working model may predict the label names themselves or integer
        # class indices (e.g. classes.index(lab) training labels). Normalise
        # both sides to class indices before scoring so either encoding is
        # graded fairly on genuine holdout accuracy.
        y_idx = np.asarray([classes.index(lab) for lab, _ in te], dtype=np.int64)
        preds = np.atleast_1d(clf.predict(X))

        def _to_idx(p):
            try:
                if isinstance(p, (str, bytes, np.str_, np.bytes_)):
                    return classes.index(str(p))
                return int(p)
            except Exception:
                return -1

        yhat = np.asarray([_to_idx(p) for p in preds], dtype=np.int64)
        acc = float((yhat == y_idx).mean())
        return local, E, v, acc
    except Exception as ex:
        local.append("exception: %r" % ex)
        return local, None, None, None

# ---- visible on /app ----
visE, visV, visAcc = None, None, None
vis_local, visE, visV, visAcc = structure_ok("/app", "/app/data/reviews.tsv")
if vis_local:
    for m in vis_local:
        fail("VISIBLE " + m)
else:
    # embeddings-capture-structure (semantic) check on the shipped corpus
    anchors = [("bzbrlrlqc", "dxdbzwx"), ("ddrkg", "wbkwrhvqr")]
    if all(a in visV.word2idx and b in visV.word2idx for a, b in anchors):
        def cosi(a, b):
            ia, ib = visV.word2idx[a], visV.word2idx[b]
            va, vb = visE[ia], visE[ib]
            return float(np.dot(va, vb) / (np.linalg.norm(va) * np.linalg.norm(vb)))
        s1 = cosi("bzbrlrlqc", "dxdbzwx")
        s2 = cosi("ddrkg", "wbkwrhvqr")
        x1 = cosi("bzbrlrlqc", "wbkwrhvqr")
        x2 = cosi("ddrkg", "dxdbzwx")
        if not ((s1 - x1) > 0.1 and (s2 - x2) > 0.1):
            fail("embedding semantics: within-class sim not above cross-class "
                 "(s=%.3f/%.3f x=%.3f/%.3f)" % (s1, s2, x1, x2))
        if visAcc < 0.85:
            fail("visible classifier accuracy %.3f < 0.85" % visAcc)
    else:
        fail("shipped-anchor tokens missing from vocab")

if not failmsgs:
    reward += 0.5
else:
    for m in failmsgs:
        print("  (visible already failed)")

# ---------------------------------------------------------------- hidden ---
for case, weight, outn in [
        ("case1.json", 0.25, "o1"),
        ("case2.json", 0.25, "o2")]:
    path = os.path.join(HID, case)
    if not os.path.exists(path):
        fail("missing hidden %s" % case); continue
    cfg = json.load(open(path))
    tsvin = "/tmp/%s.tsv" % outn
    outd = "/tmp/%sout" % outn
    gencmd = [sys.executable, "/app/gen_corpus.py", "--out", tsvin,
              "--seed", str(cfg["seed"]), "--count", str(cfg["count"]),
              "--edge", str(cfg.get("edge", 0))]
    g = subprocess.run(gencmd, capture_output=True, text=True)
    if g.returncode != 0:
        fail("hidden %s gen failed: %s" % (case, g.stderr[-300:])); continue
    # execute the deliverable runner on the hidden corpus
    if not os.path.exists("/app/run.sh"):
        fail("hidden %s: /app/run.sh absent" % case); continue
    r = subprocess.run(["bash", "/app/run.sh", tsvin, outd],
                       capture_output=True, text=True, cwd="/app")
    if r.returncode != 0:
        fail("hidden %s: run.sh failed: %s" % (case, r.stderr[-500:])); continue
    hlocal, E, v, acc = structure_ok(outd, tsvin)
    if hlocal:
        for m in hlocal[:6]:
            fail("hidden %s %s" % (case, m))
    else:
        floor = cfg.get("acc_floor", 0.65)
        if acc < floor:
            fail("hidden %s accuracy %.3f < %.2f" % (case, acc, floor))
        else:
            reward += weight
            print("hidden %s PASS acc=%.3f" % (case, acc))

reward = round(min(reward, 1.0), 4)
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("%.4f\n" % reward)
print("REWARD=%.4f" % reward)
sys.exit(0)
PY
