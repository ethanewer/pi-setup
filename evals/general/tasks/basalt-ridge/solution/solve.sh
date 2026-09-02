#!/usr/bin/env bash
# RIDGE oracle: genuinely debug the two seeded defects in the shipped
# framework, then run the documental training job to produce the remaining
# deliverables (model.pt, train.log).
#
# Bug 1: `attention_softmax` exponentiates the raw logits (no per-axis max
#        subtraction), so large-magnitude bags overflow to NaN.
# Bug 2: the BCE objective's backward gradient carries the wrong sign, so
#        full-batch SGD pushes parameters the wrong way and never converges.
set -euo pipefail
cd /app

python3 - <<'PY'
import pathlib
p = pathlib.Path('/app/framework.py')
src = p.read_text()

# --- repair bug 1: stable max-subtracted softmax + logsumexp ---
old1 = """    x = np.asarray(logits, dtype=float)
    # naive: exp() taken directly on the raw logits (no max subtraction)
    e = np.exp(x)
    s = np.sum(e, axis=axis, keepdims=True)
    p = e / s
    dt = dtype_for(dtype)
    lse = np.log(s)"""
new1 = """    x = np.asarray(logits, dtype=float)
    # stable: subtract the per-axis max so exp() cannot overflow
    # at extreme logit magnitudes (~1e4 .. 1e-300).
    m = np.max(x, axis=axis, keepdims=True)
    e = np.exp(x - m)
    s = np.sum(e, axis=axis, keepdims=True)
    p = e / s
    dt = dtype_for(dtype)
    lse = np.log(s) + m"""
assert old1 in src, "attention_softmax block not found"
src = src.replace(old1, new1)

# --- repair bug 2: correct BCE backward sign (SGD moves loss downhill) ---
old2 = "grad = -float((o - target) / (o * (1.0 - o) + epsilon))"
new2 = "grad = float((o - target) / (o * (1.0 - o) + epsilon))"
assert old2 in src, "BCE sign line not found"
src = src.replace(old2, new2)

p.write_text(src)
print("framework.py repaired (stable softmax + BCE gradient sign)")
PY

# --- run the required training job, producing model.pt and train.log ---
python3 /app/train.py \
  --dims 8 --bags 24 --max-items 12 --noise 0.4 \
  --iters 500 --lr 0.05 --dtype fp32 --seed 7 \
  --target 0.02 --out /app/model.pt --log /app/train.log
