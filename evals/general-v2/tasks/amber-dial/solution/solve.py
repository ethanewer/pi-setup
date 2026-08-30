#!/usr/bin/env python3
"""amber-dial — Verbarium small-model serving layer.

The lattice-team at "Nighthollow" keeps a tiny on-device recommender. This
program supplies the whole small-model serving layer for it:

  * RowParallelLinear / ColumnParallelLinear  -- hand-rolled tensor-parallel
    (model-parallel) linear layers that shard a weight matrix along the input
    or column dimension, all-reduce / all-gather partial sums, and keep the
    bias consistent, producing outputs and gradients that are numerically
    identical to a dense linear layer.
  * PolicyWDLEngine -- a small forward model (built from the parallel layers)
    whose outputs are a "policy_logits" head (legal-move logits) and a "value"
    head that holds post-softmax outcome probabilities.
  * A Flask POST /classify endpoint returning a documented structured
    sentiment classification.

Everything is deterministic (fixed seeds), all CLI modes write literal outputs
under /app, and every result visible in /app/answer.json is re-derivable by
re-running the program. The work forms a three-stage chain:
  1) implement the two tensor-parallel layers,
  2) build + train the two-head engine on top of them,
  3) stand up the /classify endpoint.
"""
import argparse
import json
import math
import os
import re
import sys

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from flask import Flask, jsonify, request

# ----------------------------------------------------------------------------
# Fixed architecture constants (documented in instruction.md).
# ----------------------------------------------------------------------------
NUM_LEGAL_MOVES = 2156      # width of the policy (legal-moves) head
IN_FEATURES = 64            # dimension of one input feature vector
HIDDEN = 128                # internal hidden width used by the engine
WORLD_SIZE = 8              # number of parallel ranks the engine is sharded across
INIT_SCALE = 0.05           # uniform scale used for parallel-layer weight init


# ----------------------------------------------------------------------------
# 1) Tensor-parallel (model-parallel) linear layers.
# ----------------------------------------------------------------------------
class RowParallelLinear(nn.Module):
    """Row-parallel linear layer.

    The weight W is (out_features, in_features). It is sharded along the
    *input* (feature) dimension: rank r owns the column block
    W[:, r*chunk:(r+1)*chunk]. Each rank computes the partial product of its
    input chunk with its weight block; the per-rank partial results are
    all-reduced (summed) and the *full* bias is added on every rank, so that

        forward(x) == x @ W^T + bias
    """

    def __init__(self, in_features, out_features, world_size, bias=True):
        super().__init__()
        if in_features % world_size != 0:
            raise ValueError(
                "RowParallelLinear: in_features=%d must be divisible by "
                "world_size=%d" % (in_features, world_size))
        self.in_features = int(in_features)
        self.out_features = int(out_features)
        self.world_size = int(world_size)
        self.chunk = self.in_features // self.world_size
        self.W = nn.Parameter(torch.randn(self.out_features, self.in_features) * INIT_SCALE)
        self.bias = nn.Parameter(torch.zeros(self.out_features)) if bias else None

    def shard_of(self, rank):
        c = self.chunk
        lo, hi = rank * c, (rank + 1) * c
        return self.W[:, lo:hi]

    def sharded_input(self, x, rank):
        c = self.chunk
        return x[:, rank * c:(rank + 1) * c]

    def sharded_grad_weight(self, x, grad_of_out, rank):
        """The dL/dW slice ## owned by rank (a chunk of columns of the dense grad)."""
        return grad_of_out.t() @ self.sharded_input(x, rank)

    def forward(self, x):
        partials = []
        for r in range(self.world_size):
            partial = self.sharded_input(x, r) @ self.shard_of(r).t()
            partials.append(partial)
        y = torch.stack(partials, dim=0).sum(0)  # all-reduce over ranks
        if self.bias is not None:
            y = y + self.bias.view(1, -1)
        return y


class ColumnParallelLinear(nn.Module):
    """Column-parallel ('tensor-parallel') linear layer.

    The weight W is (out_features, in_features). It is sharded along the
    *output* (column) dimension: rank r owns the row slice
    W[r*chunk:(r+1)*chunk, :].  Each rank computes its local output block, the
    blocks are all-gathered (concatenated) along the output dimension, and the
    matching bias slice is added, so that

        forward(x) == x @ W^T + bias

    The sharded-gradient routine (`sharded_grad_weight`) returns exactly the rank
    block of the dense gradient dL/dW.
    """

    def __init__(self, in_features, out_features, world_size, bias=True):
        super().__init__()
        if out_features % world_size != 0:
            raise ValueError(
                "ColumnParallelLinear: out_features=%d must be divisible by "
                "world_size=%d" % (out_features, world_size))
        self.in_features = int(in_features)
        self.out_features = int(out_features)
        self.world_size = int(world_size)
        self.chunk = self.out_features // self.world_size
        self.W = nn.Parameter(torch.randn(self.out_features, self.in_features) * INIT_SCALE)
        self.bias = nn.Parameter(torch.zeros(self.out_features)) if bias else None

    def shard_of(self, rank):
        c = self.chunk
        return self.W[rank * c:(rank + 1) * c, :]

    def sharded_grad_weight(self, x, grad_of_out, rank):
        """The dL/dW slice of this rank (chunk of the *rows* of the dense W)."""
        c = self.chunk
        g = grad_of_out[:, rank * c:(rank + 1) * c]
        return g.t() @ x

    def forward(self, x):
        blocks = []
        for r in range(self.world_size):
            blocks.append(x @ self.shard_of(r).t())
        y = torch.cat(blocks, dim=1)  # all-gather along the output dimension
        if self.bias is not None:
            y = y + self.bias.view(1, -1)
        return y


# ----------------------------------------------------------------------------
# 2) Two-head forward engine (policy logits + post-softmax value).
# ----------------------------------------------------------------------------
class PolicyWDLEngine(nn.Module):
    """A small two-headed forward network sharded over WORLD_SIZE ranks.

    forward(x) -> {"policy_logits": (B, NUM_LEGAL_MOVES) raw logits,
                   "value":          (B, 3)        post-softmax probabilities}
    The value head logits span [loss, draw, win]; value is their softmax, so
    every value row sums to exactly 1.
    """

    def __init__(self, in_features=IN_FEATURES, hidden=HIDDEN,
                 world_size=WORLD_SIZE, num_moves=NUM_LEGAL_MOVES):
        super().__init__()
        self.in_features = int(in_features)
        self.hidden = int(hidden)
        self.world_size = int(world_size)
        self.num_moves = int(num_moves)
        self.c1 = ColumnParallelLinear(self.in_features, self.hidden, self.world_size)
        self.c2 = RowParallelLinear(self.hidden, self.hidden, self.world_size)
        self.ln = nn.LayerNorm(self.hidden)
        self.policy_head = nn.Linear(self.hidden, self.num_moves)
        self.value_head = nn.Linear(self.hidden, 3)

    def forward(self, x):
        h = torch.relu(self.c1(x))
        h = torch.relu(self.c2(h))
        h = self.ln(h)
        policy_logits = self.policy_head(h)
        value_logits = self.value_head(h)
        value = torch.softmax(value_logits, dim=-1)
        return {"policy_logits": policy_logits, "value": value}


# ----------------------------------------------------------------------------
# Tiny synthesis: a separable dataset the engine is trained to classify.
# ----------------------------------------------------------------------------
_TRAINING_SEED = 1013


def build_dataset(n=600, seed=_TRAINING_SEED, in_features=IN_FEATURES,
                  num_moves=NUM_LEGAL_MOVES, device="cpu"):
    g = torch.Generator().manual_seed(seed)
    X = torch.randn(n, in_features, generator=g)
    Wp = torch.randn(in_features, num_moves, generator=g)
    move_logits = X @ Wp
    y_move = move_logits.argmax(dim=1)
    Wv = torch.randn(in_features, 3, generator=g)
    y_value = (X @ Wv).argmax(dim=1)
    return X.to(device), y_move.to(device), y_value.to(device)


def train_engine(steps=320, batch=64, lr=2e-3, reporter=None):
    torch.manual_seed(7)
    model = PolicyWDLEngine()
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    X, y_move, y_value = build_dataset()
    n = X.shape[0]
    loss_f = nn.CrossEntropyLoss()
    for step in range(steps):
        idx = torch.randperm(n)[:min(batch, n)]
        xb, mvb, yvb = X[idx], y_move[idx], y_value[idx]
        out = model(xb)
        loss = loss_f(out["policy_logits"], mvb) + loss_f(out["value"], yvb)
        opt.zero_grad()
        loss.backward()
        opt.step()
    with torch.no_grad():
        out_all = model(X)
        pmove = out_all["policy_logits"].argmax(dim=1)
        pval = out_all["value"].argmax(dim=1)
        policy_acc = (pmove == y_move).float().mean().item()
        value_acc = (pval == y_value).float().mean().item()
        rowsum_err = (out_all["value"].sum(dim=1) - 1.0).abs().max().item()
    if reporter:
        reporter(policy_acc=policy_acc, value_acc=value_acc, rowsum_err=rowsum_err)
    return model, {"policy_acc": policy_acc, "value_acc": value_acc,
                   "value_rowsum_abs_err": rowsum_err}


# ----------------------------------------------------------------------------
# Parallel-layer self-check used to populate /app/answer.json and as the
# `--validate-parallel` sub-command the verifier re-runs on hidden inputs.
# ----------------------------------------------------------------------------
def validate_parallel(in_features, out_features, world_size, seed, batch, x=None):
    """Return a serializable dict of tensor-parallel vs dense equivalence."""
    if in_features % world_size != 0:
        return {"ok": False, "reason": "nondivisible_input",
                "in_features": in_features, "world_size": world_size,
                "out_features": out_features}
    if out_features % world_size != 0:
        return {"ok": False, "reason": "nondivisible_output",
                "in_features": in_features, "world_size": world_size,
                "out_features": out_features}
    torch.manual_seed(seed)
    row = RowParallelLinear(in_features, out_features, world_size)
    col = ColumnParallelLinear(in_features, out_features, world_size)
    if x is None:
        torch.manual_seed(seed)
        x = torch.randn(batch, in_features)
    with torch.no_grad():
        y_row = row(x)
        y_col = col(x)
        dense_row = F.linear(x, row.W, row.bias)
        dense_col = F.linear(x, col.W, col.bias)
        row_fwd_err = float((y_row - dense_row).abs().max().item())
        col_fwd_err = float((y_col - dense_col).abs().max().item())

    grad = torch.ones_like(y_row)
    with torch.no_grad():
        dense_grad_W = grad.t() @ x                      # (out, in)
        row_grads = torch.cat([row.sharded_grad_weight(x, grad, r) for r in range(world_size)], dim=1)
        col_grads = torch.cat([col.sharded_grad_weight(x, grad, r) for r in range(world_size)], dim=0)
        row_grad_err = float((row_grads - dense_grad_W).abs().max().item())
        col_grad_err = float((col_grads - dense_grad_W).abs().max().item())

    return {
        "ok": True,
        "world_size": world_size,
        "in_features": in_features,
        "out_features": out_features,
        "seed": seed,
        "row_forward_max_abs_diff": row_fwd_err,
        "col_forward_max_abs_diff": col_fwd_err,
        "row_grad_max_abs_diff": row_grad_err,
        "col_grad_max_abs_diff": col_grad_err,
        "y_row": y_row.detach().cpu().numpy().reshape(-1).round(6).tolist(),
        "y_col": y_col.detach().cpu().numpy().reshape(-1).round(6).tolist(),
    }


# ---------------------------------------------------------------------------
# 3) The /classify heuristic classifier.
# ---------------------------------------------------------------------------
POSITIVE_WORDS = {"good", "great", "excellent", "fast", "clean", "strong",
                  "stable", "improved", "brilliant", "liked"}
NEGATIVE_WORDS = {"bad", "worst", "poor", "slow", "broken", "fail", "late",
                  "drop", "clunky", "buggy"}
NEUTRAL_WORDS = {"okay", "fine", "average", "same", "normal", "steady"}


def tokenize(text):
    return re.findall(r"[a-z']+", (text or "").lower())


def classify(text):
    """Compute label + per-class confidence for a text string."""
    if text is None or str(text).strip() == "":
        return {"label": "neutral",
                "confidence": {"positive": 1.0 / 3.0, "negative": 1.0 / 3.0,
                               "neutral": 1.0 / 3.0}}
    toks = tokenize(str(text))
    pos = sum(1 for t in toks if t in POSITIVE_WORDS)
    neg = sum(1 for t in toks if t in NEGATIVE_WORDS)
    neu = sum(1 for t in toks if t in NEUTRAL_WORDS)
    if pos > neg:
        label = "positive"
    elif pos < neg:
        label = "negative"
    else:
        label = "neutral" if neu > 0 else "positive"
    raw = {"positive": pos + 1, "negative": neg + 1, "neutral": neu + 1}
    total = float(raw["positive"] + raw["negative"] + raw["neutral"])
    conf = {
        "positive": round(raw["positive"] / total, 6),
        "negative": round(raw["negative"] / total, 6),
        "neutral": round(raw["neutral"] / total, 6),
    }
    return {"label": label, "confidence": conf}


def create_app():
    app = Flask("amber_dial")

    @app.route("/classify", methods=["POST"])
    def classify_endpoint():
        if not request.is_json:
            return jsonify({"error": "content-type-not-json"}), 400
        body = request.get_json(silent=True)
        if not isinstance(body, dict) or not isinstance(body.get("text"), str):
            return jsonify({"error": "missing-text"}), 400
        return jsonify(classify(body["text"]))

    @app.route("/", methods=["GET"])
    def index():
        return jsonify({"service": "amber-dial", "endpoints": ["/classify"]})

    return app


# ---------------------------------------------------------------------------
# CLI + run
# ---------------------------------------------------------------------------
def default_run(report_path="/app/answer.json", model_path="/app/model.pt"):
    model, train_stats = train_engine()
    torch.save(model.state_dict(), model_path)
    with torch.no_grad():
        inp = torch.randn(9, IN_FEATURES)
        out = model(inp)
        rowsum_err = float((out["value"].sum(dim=1) - 1.0).abs().max().item())

    par = validate_parallel(IN_FEATURES, HIDDEN, WORLD_SIZE, seed=77, batch=9)

    result = {
        "arch": {
            "in_features": IN_FEATURES, "hidden": HIDDEN,
            "world_size": WORLD_SIZE, "num_moves": NUM_LEGAL_MOVES,
        },
        "train": {
            "policy_top1_accuracy": train_stats["policy_acc"],
            "value_top1_accuracy": train_stats["value_acc"],
        },
        "forward": {"value_rowsum_max_abs_err": rowsum_err},
        "parallel": {
            "ok": par["ok"],
            "row_forward_max_abs_diff": par["row_forward_max_abs_diff"],
            "col_forward_max_abs_diff": par["col_forward_max_abs_diff"],
            "row_grad_max_abs_diff": par["row_grad_max_abs_diff"],
            "col_grad_max_abs_diff": par["col_grad_max_abs_diff"],
        },
        "flask_empty_label": classify("")["label"],
        "model_saved": model_path,
    }
    with open(report_path, "w") as fh:
        json.dump(result, fh, indent=2)
    return result


def cmd_validate(args):
    x = None
    if args.input:
        x = torch.from_numpy(np.load(args.input).astype("float32"))
    print(json.dumps(validate_parallel(args.in_features, args.out_features,
                                       args.world_size, args.seed, args.batch,
                                       x=x)))


def cmd_infer(args):
    try:
        mat = np.load(args.infer)
    except Exception as exc:
        print(json.dumps({"error": "cannot-load-features", "detail": str(exc)}))
        sys.exit(2)
    if mat.ndim != 2 or mat.shape[1] != IN_FEATURES:
        print(json.dumps({"error": "bad-shape", "shape": list(mat.shape),
                          "required": [ "*", IN_FEATURES]}))
        sys.exit(2)
    model = PolicyWDLEngine()
    sd = torch.load(args.model, map_location="cpu",
                    weights_only=True)
    model.load_state_dict(sd)
    model.eval()
    with torch.no_grad():
        out = model(torch.from_numpy(mat.astype("float32")))
    poly = out["policy_logits"].detach().cpu().numpy()
    val = out["value"].detach().cpu().numpy()
    rows = int(mat.shape[0])
    resp = {
        "n_inputs": rows,
        "in_features": IN_FEATURES,
        "policy_logits_shape": [rows, int(poly.shape[1])],
        "value_shape": [rows, 3],
        "value_rowsum_max_abs_err": float(np.abs(val.sum(axis=1) - 1.0).max())
        if rows else 0.0,
        "policy_finite": bool(np.isfinite(poly).all()),
        "all_in_unit_interval": bool(((val >= 0.0) & (val <= 1.0)).all()),
    }
    print(json.dumps(resp))


def cmd_serve(args):
    app = create_app()
    app.run(host="127.0.0.1", port=int(args.serve), threaded=True, debug=False)


def main():
    ap = argparse.ArgumentParser(prog="amber-dial-solver",
                                 description="Nobel hollow small-model serving layer")
    ap.add_argument("--validate-parallel",
                    action="store_true",
                    help="check parallel layers match a dense linear (hidden use)")
    ap.add_argument("--infer", metavar="FEATURES_NPY", default=None,
                    help="run the saved engine forward on a (N,64) .npy array")
    ap.add_argument("--serve", metavar="PORT", default=None,
                    help="run the Flask /classify endpoint on PORT")
    ap.add_argument("--model", default="/app/model.pt", help="model checkpoint path")
    ap.add_argument("--in-features", type=int, default=16)
    ap.add_argument("--out-features", type=int, default=24)
    ap.add_argument("--world-size", type=int, default=4)
    ap.add_argument("--seed", type=int, default=6)
    ap.add_argument("--batch", type=int, default=12)
    ap.add_argument("--input", default=None,
                    help="optional (batch,in_features) .npy input for --validate-parallel")

    args = ap.parse_args()
    if args.validate_parallel:
        cmd_validate(args)
    elif args.infer:
        cmd_infer(args)
    elif args.serve:
        cmd_serve(args)
    else:
        default_run()
        print("OK amber-dial (answer.json + model.pt written)")
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())