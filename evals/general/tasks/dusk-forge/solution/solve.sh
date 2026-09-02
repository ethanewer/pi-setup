#!/bin/bash
# Oracle for dusk-forge: train a small ReLU MLP with plain numpy (fixed
# seed), publish a weights-only float32 artifact under /app/model (well under
# the 100 KB budget), and write /app/predict.py. Then smoke-run the loader on
# the held-out eval. Never reads /tests.
set -eu

MODEL_DIR="/app/model"
PREDICT="/app/predict.py"

mkdir -p "$MODEL_DIR"

# ---- 1. the loader/predictor deliverable ---------------------------------
cat > "$PREDICT" <<'PY'
"""Load the Dusk-Forge calibration model and predict a batch of rows.

Usage: python3 predict.py <model_dir> <input_npz> <output_npz>
"""
import sys

import numpy as np


def load_model(model_dir):
    w = np.load(model_dir + "/weights.npz")
    return [(w["W1"], w["b1"]), (w["W2"], w["b2"]), (w["W3"], w["b3"])]


def forward(layers, X):
    a = X
    for i, (W, b) in enumerate(layers):
        z = a @ W.astype(np.float64) + b.astype(np.float64)
        a = np.maximum(z, 0.0) if i < len(layers) - 1 else z
    return a


def main(argv):
    if len(argv) != 4:
        print("usage: python3 predict.py <model_dir> <input_npz> <output_npz>",
              file=sys.stderr)
        return 2
    model_dir, in_npz, out_npz = argv[1], argv[2], argv[3]
    layers = load_model(model_dir)
    X = np.load(in_npz)["X"].astype(np.float64)
    pred = forward(layers, X).ravel()
    np.savez(out_npz, pred=pred.astype(np.float32))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

# ---- 2. train (deterministic, CPU numpy) and publish the artifact ---------
python3 - <<'PY'
import numpy as np

data = np.load("/opt/forge/data/train.npz")
X = data["X"].astype(np.float64)
y = data["y"].astype(np.float64).reshape(-1, 1)

H1, H2 = 160, 80
rng = np.random.default_rng(20240917)
params = [
    [rng.normal(0, np.sqrt(2.0 / 24), (24, H1)), np.zeros(H1)],
    [rng.normal(0, np.sqrt(2.0 / H1), (H1, H2)), np.zeros(H2)],
    [rng.normal(0, np.sqrt(2.0 / H2), (H2, 1)), np.zeros(1)],
]
m = [(np.zeros_like(w), np.zeros_like(b)) for w, b in params]
v = [(np.zeros_like(w), np.zeros_like(b)) for w, b in params]
lr, b1c, b2c, eps = 2e-3, 0.9, 0.999, 1e-8


def forward(Xp):
    acts, Zs = [Xp], []
    for i, (w, b) in enumerate(params):
        Z = acts[-1] @ w + b
        Zs.append(Z)
        acts.append(np.maximum(Z, 0.0) if i < 2 else Z)
    return acts, Zs


EPOCHS = 600
for epoch in range(1, EPOCHS + 1):
    acts, Zs = forward(X)
    diff = acts[-1] - y
    G = 2 * diff / len(y)
    grads = [None] * 3
    for i in (2, 1, 0):
        grads[i] = (acts[i].T @ G, G.sum(0))
        if i > 0:
            G = (G @ params[i][0].T) * (Zs[i - 1] > 0)
    for i in range(3):
        mw, mb = m[i]
        vw, vb = v[i]
        gw, gb = grads[i]
        mw *= b1c; mw += (1 - b1c) * gw
        mb *= b1c; mb += (1 - b1c) * gb
        vw *= b2c; vw += (1 - b2c) * gw * gw
        vb *= b2c; vb += (1 - b2c) * gb * gb
        params[i][0] -= lr * (mw / (1 - b1c ** epoch)) / (np.sqrt(vw / (1 - b2c ** epoch)) + eps)
        params[i][1] -= lr * (mb / (1 - b1c ** epoch)) / (np.sqrt(vb / (1 - b2c ** epoch)) + eps)
    if epoch % 200 == 0:
        print("epoch", epoch, "train_rmse %.4f" % float(np.sqrt(np.mean(diff ** 2))))

# publish weights-only, float32 (67 KB, comfortably under the 100 KB gate)
np.savez("/app/model/weights.npz",
         W1=params[0][0].astype(np.float32), b1=params[0][1].astype(np.float32),
         W2=params[1][0].astype(np.float32), b2=params[1][1].astype(np.float32),
         W3=params[2][0].astype(np.float32), b3=params[2][1].astype(np.float32))

import os
total = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk("/app/model") for f in fs)
print("artifact bytes:", total)
assert total <= 102400, "artifact over budget"
PY

# ---- 3. smoke-run the deliverable loader on the held-out eval -------------
python3 "$PREDICT" "$MODEL_DIR" /opt/forge/data/eval.npz /tmp/forge_smoke.npz
python3 - <<'PY'
import numpy as np
pred = np.load("/tmp/forge_smoke.npz")["pred"]
y = np.load("/opt/forge/data/eval.npz")["y"]
rmse = float(np.sqrt(np.mean((pred.astype(np.float64) - y) ** 2)))
print("eval rmse: %.4f" % rmse)
assert pred.shape == y.shape
assert rmse <= 0.45, "oracle below quality gate"
PY

echo "solve.sh done -> $PREDICT and $MODEL_DIR"
ls -l "$PREDICT"; du -sb "$MODEL_DIR" || du -sk "$MODEL_DIR"
