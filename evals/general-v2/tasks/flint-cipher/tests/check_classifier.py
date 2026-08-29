#!/usr/bin/env python3
"""Hidden-check for Stage 3 (multilingual classifier deployment).

(1) The frozen /app/classifier_snapshot.npz is run through the agent's
    /app/predict.py on a held-out document set the model never saw, and must
    reach overall >= 0.90 and per-language >= 0.85 accuracy.
(2) /app/train.py must be re-runnable end-to-end (it produces a valid snapshot
    and metrics).
(3) The shipped /app/eval_metrics.json must describe the dev split with valid
    overall_accuracy (>=0.90) and per_language (each of en,fr,de,es >= 0.85).

The instruction contract requires that the snapshot carry a coherent frozen
classifier (feature list, class labels, coefficient matrix, intercept), so the
structural check accepts any reasonable key spelling rather than demanding one
exact .npz key.  The documented train.py CLI is --train/--dev/--snapshot/
--metrics; --seed is an optional documented extension, so if the agent's CLI
rejects it we retry with the documented flags only.
"""
import json
import os
import subprocess
import sys

SNAPSHOT = "/app/classifier_snapshot.npz"
DEV_HIDDEN = "/tests/hidden/dev_hidden.tsv"

OVERALL_NEED = 0.90
PER_NEED = 0.85
REQUIRED_LANGS = {"en", "fr", "de", "es"}

# Alias groups for the frozen classifier state (documented keys first).
FEATURE_KEYS = ["feature", "feature_names", "features"]
CLASS_KEYS = ["classes", "labels", "class_names"]
COEF_KEYS = ["coef", "coefficients", "coef_"]
INTERCEPT_KEYS = ["intercept", "intercepts", "intercept_"]

TRAIN_BASE = [
    "python3", "/app/train.py",
    "--train", "/app/data/train.tsv",
    "--dev", "/app/data/dev.tsv",
    "--snapshot", "/tmp/re_train.npz",
    "--metrics", "/tmp/re_metrics.json",
]


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def pick_key(data, aliases):
    """Return (key, value) for the first alias present in the npz, else (None, None)."""
    for name in aliases:
        if name in data.files:
            return name, data[name]
    return None, None


def snapshot_structural_check(path):
    """The npz must carry a coherent frozen classifier: a non-empty feature
    list, class labels (n_classes), a coefficient matrix (n_classes x
    n_features) and an intercept vector (n_classes)."""
    import numpy as np
    try:
        data = np.load(path, allow_pickle=True)
    except Exception as exc:
        print("FAIL re-trained snapshot unreadable: %s" % exc)
        return False
    fkey, fval = pick_key(data, FEATURE_KEYS)
    ckey, cval = pick_key(data, CLASS_KEYS)
    wkey, wval = pick_key(data, COEF_KEYS)
    ikey, ival = pick_key(data, INTERCEPT_KEYS)
    if fkey is None or ckey is None or wkey is None or ikey is None:
        print("FAIL snapshot missing required state; keys present: %s"
              % sorted(data.files))
        return False
    try:
        nf = len(fval)
        ncl = len(cval)
        coef = np.asarray(wval, dtype=float)
        intercept = np.asarray(ival, dtype=float)
    except Exception as exc:
        print("FAIL snapshot state not array-coercible: %s" % exc)
        return False
    if nf <= 0:
        print("FAIL snapshot carries no features")
        return False
    if coef.ndim != 2 or coef.shape[1] != nf:
        print("FAIL snapshot coef shape %s != n_classes x %d features"
              % (coef.shape, nf))
        return False
    if ncl <= 0 or coef.shape[0] != ncl:
        print("FAIL snapshot classes %d != coef rows %d" % (ncl, coef.shape[0]))
        return False
    if intercept.ndim != 1 or intercept.shape[0] != ncl:
        print("FAIL snapshot intercept shape %s != classes %d"
              % (intercept.shape, ncl))
        return False
    return True


def train_rerun():
    """Re-run the agent's train.py via the documented CLI (--train/--dev/
    --snapshot/--metrics).  --seed is an optional documented extension; if the
    agent's CLI rejects it, retry with the documented flags only."""
    rc, out, err = run(TRAIN_BASE + ["--seed", "0"])
    if rc == 0:
        return True
    for stale in ("/tmp/re_train.npz", "/tmp/re_metrics.json"):
        if os.path.exists(stale):
            os.remove(stale)
    rc2, out2, err2 = run(TRAIN_BASE)
    if rc2 == 0:
        return True
    print("FAIL train.py rc=%d %s | retry-without-seed rc=%d %s"
          % (rc, err[-400:], rc2, err2[-400:]))
    return False


def main():
    # --- run the frozen model on held-out docs ---
    rc, out, err = run(["python3", "/app/predict.py", SNAPSHOT, DEV_HIDDEN])
    if rc != 0:
        print("FAIL predict rc=%d %s" % (rc, err[-400:])); return 1
    preds = [ln for ln in out.splitlines() if ln.strip()]
    true = []
    with open(DEV_HIDDEN, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            true.append(line.split("\t", 1)[0])
    if len(preds) != len(true):
        print("FAIL prediction count %d != %d" % (len(preds), len(true))); return 1

    bylang = {}
    correct = 0
    for t, pr in zip(true, preds):
        if pr == t:
            correct += 1
            bylang.setdefault(t, [0, 0])[0] += 1
        else:
            bylang.setdefault(t, [0, 0])
        bylang[t][1] += 1
    overall = correct / len(true)
    perl = {k: ok / n for k, (ok, n) in bylang.items()}
    print("  hidden overall=%.2f per_language=%s" % (overall, {k: round(v, 2) for k, v in perl.items()}))
    if overall < OVERALL_NEED:
        print("FAIL hidden overall accuracy %.2f < %.2f" % (overall, OVERALL_NEED)); return 1
    for lang, acc in perl.items():
        if acc < PER_NEED:
            print("FAIL hidden per-language %s acc %.2f < %.2f" % (lang, acc, PER_NEED)); return 1

    # --- agent's train.py re-runnable (documented CLI, --seed optional) ---
    if not train_rerun():
        return 1
    if not snapshot_structural_check("/tmp/re_train.npz"):
        return 1

    # --- shipped eval_metrics ---
    try:
        m = json.load(open("/app/eval_metrics.json"))
    except Exception as exc:
        print("FAIL eval_metrics.json unreadable:", exc); return 1
    if "overall_accuracy" not in m or "per_language" not in m:
        print("FAIL eval_metrics.json keys missing"); return 1
    pl = m["per_language"]
    if not isinstance(pl, dict):
        print("FAIL per_language is not a dict"); return 1
    missing = REQUIRED_LANGS - set(pl.keys())
    if missing:
        print("FAIL reported per_language missing languages:", sorted(missing)); return 1
    if m["overall_accuracy"] < OVERALL_NEED:
        print("FAIL reported overall accuracy %.2f" % m["overall_accuracy"]); return 1
    for lang, acc in pl.items():
        if acc < PER_NEED:
            print("FAIL reported per-language %s %.2f" % (lang, acc)); return 1

    print("PASS classifier-hidden: overall/=%.2f per-lang ok, train re-runnable, metrics ok"
          % overall)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())