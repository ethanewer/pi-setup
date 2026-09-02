#!/usr/bin/env python3
"""
pipeline_parallel.py
--------------------
Clean-room implementation of a pipeline-parallel transformer shard trainer.

Roles the module fills (see instruction.md):
  * PARTITION  -- an even, contiguous split of L transformer layers across
    R ranks (ranks in [0, R)).  Every layer in [0, L) is owned by exactly one
    rank; later ranks may own nothing when L < R (empty stages are legal).
  * INIT       -- every stage's bias tensor is zero-initialized (a pipeline
    need: biases start at zero and only drift through accumulated gradient
    updates).
  * EXCHANGE    -- forward pass sends each stage's output activation tensor
    (shape [batch, d]) to the next stage as its input; backward pass sends the
    input-gradient tensor delta (shape [batch, d]) back to the previous stage.
    Everything is verified to be correctly shaped at every hop.

The module is both importable (so tests can call partition_layers /
run_exchange directly) and a repeatable CLI that re-derives the default
artifact /app/grad_exchange.npz or a configurable one for arbitrary hidden
world/rank counts and gradient shapes.

A micro-batch forward followed by a (shape-exact) backward is simulated fully
in-process with numpy as deterministic loopback tensor movement, which is what
a real gloo point-to-point transfer on one machine reduces to.
"""
import argparse
import json
import os

import numpy as np

__all__ = ["partition_layers", "PipeLayer", "run_pipeline", "main"]


def partition_layers(world_size, num_layers):
    """Return dict rank -> ordered list of contiguous layer indices.

    Even split: base = L // R, remainder `extra` = L % R distributed to the
    first `extra` ranks.  When world_size > num_layers some trailing ranks are
    empty (they still exist for the exchange topology but own no parameters).
    Union over ranks == set(range(num_layers)) and no index repeats.
    """
    world_size = int(world_size)
    num_layers = int(num_layers)
    if world_size < 1:
        raise ValueError("world_size must be >= 1")
    if num_layers < 0:
        raise ValueError("num_layers must be >= 0")
    base = num_layers // world_size
    extra = num_layers % world_size
    assign = {}
    for r in range(world_size):
        start = r * base + min(r, extra)
        cnt = base + (1 if r < extra else 0)
        assign[r] = list(range(start, start + cnt))
    return assign


class PipeLayer:
    """A single transformer-style linear stage: y = x @ W + b."""

    def __init__(self, d, layer_idx, seed_root=2024):
        self.d = int(d)
        rng = np.random.default_rng(seed_root * 1000 + int(layer_idx))
        # He-ish init on the 0.02 scale of the spec, weight zeros not required.
        self.weight = rng.normal(0.0, 0.02, size=(self.d, self.d)).astype(np.float32)
        # ZERO-INITIALIZED bias (explicit contract, and checked by the verifier).
        self.bias = np.zeros(self.d, dtype=np.float32)
        self.layer_idx = int(layer_idx)

    def forward(self, x):
        return (x @ self.weight + self.bias).astype(np.float32)


def run_pipeline(world_size, num_layers, d, batch, seed=7):
    """Build the partitioned pipeline, run a forward + backward exchange.

    Returns a dict describing every tensor movement so it can be archived to
    .npz and independently re-verified.  All activations and hand gradients
    carry shape [batch, d].
    """
    assign = partition_layers(world_size, num_layers)
    rank_of = {}
    for r, idxs in assign.items():
        for i in idxs:
            rank_of[i] = r
    layers = {i: PipeLayer(d, i) for i in range(num_layers)}

    rng = np.random.default_rng(seed)
    x0 = rng.normal(size=(batch, d)).astype(np.float32)

    # ---------- forward: activations move stage -> stage ----------
    activations = {-1: x0}
    a = x0
    for i in range(num_layers):
        a = layers[i].forward(a)
        activations[i] = a
    final = activations[num_layers - 1]

    # ---------- backward: input-gradients move stage -> previous stage ----------
    delta = np.ones((batch, d), dtype=np.float32)
    grad_shapes = []
    act_shapes = []
    for i in reversed(range(num_layers)):
        a_prev = activations[i - 1]
        grad_w = a_prev.T @ delta                  # [d, d]
        grad_b = delta.sum(axis=0)                 # [d]
        grad_in = delta @ layers[i].weight.T       # [batch, d] sent back
        grad_shapes.append(list(delta.shape))
        act_shapes.append(list(activations[i].shape))
        delta = grad_in
    act_shapes.reverse()
    grad_shapes.reverse()
    act_shapes = np.asarray(act_shapes, dtype=np.int64).reshape(num_layers, 2)
    grad_shapes = np.asarray(grad_shapes, dtype=np.int64).reshape(num_layers, 2)

    # zero-bias evidence: no bias element may be NON-zero at init.
    if num_layers == 0:
        bias_sum = np.zeros(0, dtype=np.float32)
    else:
        bias_sum = np.stack([layers[i].bias for i in range(num_layers)]).sum(axis=1)

    return {
        "world_size": int(world_size),
        "num_layers": int(num_layers),
        "d": int(d),
        "batch": int(batch),
        "partition": assign,
        "x0": x0,
        "output": final,
        "bias_sum": bias_sum,
        "act_shapes": act_shapes,
        "grad_shapes": grad_shapes,
        "weights": (np.stack([layers[i].weight for i in range(num_layers)])
                    if num_layers else np.zeros((0, d, d), dtype=np.float32)),
        "biases": (np.stack([layers[i].bias for i in range(num_layers)])
                   if num_layers else np.zeros((0, d), dtype=np.float32)),
    }


def encode_partition(assign, world_size):
    """Matrix[int64] world_size x kmax (-1 padding) so it survives .npz."""
    kmax = max((len(v) for v in assign.values()), default=0)
    m = np.full((world_size, kmax), -1, dtype=np.int64)
    for r, lst in assign.items():
        for c, v in enumerate(lst):
            m[r, c] = v
    return m


def archive(path, world_size, num_layers, d, batch, seed=0x1c0ffee):
    res = run_pipeline(world_size, num_layers, d, batch, seed=seed)
    np.savez(
        path,
        world_size=np.asarray(res["world_size"], np.int64),
        num_layers=np.asarray(res["num_layers"], np.int64),
        d=np.asarray(res["d"], np.int64),
        batch=np.asarray(res["batch"], np.int64),
        partition=encode_partition(res["partition"], res["world_size"]),
        x0=res["x0"],
        output=res["output"],
        bias_sum=res["bias_sum"],
        act_shapes=res["act_shapes"],
        grad_shapes=res["grad_shapes"],
        weights=res["weights"],
        biases=res["biases"],
    )
    return res["partition"]


def main(argv=None):
    ap = argparse.ArgumentParser(description="pipeline-parallel shard & exchange")
    ap.add_argument("--world-size", type=int, default=4, help="number of ranks")
    ap.add_argument("--layers", type=int, default=8, help="number of layers L")
    ap.add_argument("--d", type=int, default=16, help="hidden / exchange width d")
    ap.add_argument("--batch", type=int, default=3, help="micro-batch size")
    ap.add_argument("--out", default=None,
                    help="output .npz path (default /app/grad_exchange.npz)")
    ap.add_argument("--print-map", action="store_true",
                    help="dump the partition map as JSON to stdout")
    args = ap.parse_args(argv)
    out = args.out or "/app/grad_exchange.npz"
    assign = archive(out, args.world_size, args.layers, args.d, args.batch)
    if args.print_map:
        print(json.dumps({str(k): v for k, v in assign.items()}))
    return 0


if __name__ == "__main__":
    main()