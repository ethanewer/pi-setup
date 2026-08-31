#!/usr/bin/env python3
"""Fixture generator for amber-quarry: builds one .onnx calibration graph per
case plus fixed inputs and meta.

Graph (float32, opset 17), documented in the task instruction:
    h1 = x @ W1 + b1
    a1 = 0.5 * h1 * (1 + erf(h1 / sqrt(2)))          # Gelu (erf form)
    n1 = LayerNormalization(a1, g1, beta1, axis=-1, eps=1e-5)
    h2 = n1 @ W2 + b2
    a2 = 0.5 * h2 * (1 + erf(h2 / sqrt(2)))
    o1 = a2 @ W3 + b3
    out = Softmax(o1, axis=-1)

Usage: python3 gen.py <outdir> <case_id> <seed> [D] [H] [K] [B_fixed]
"""
import json
import os
import sys

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper


def gelu_subgraph(x):
    """Return the node list computing 0.5*x*(1+erf(x/sqrt(2))) from x."""
    return [
        helper.make_node("Div", [x, "c_sqrt2"], ["g_d"]),
        helper.make_node("Erf", ["g_d"], ["g_e"]),
        helper.make_node("Add", ["g_e", "c_one"], ["g_e1"]),
        helper.make_node("Mul", [x, "g_e1"], ["g_m"]),
        helper.make_node("Mul", ["g_m", "c_half"], ["g_a"]),
    ]


def build_graph(D, H, K, rng):
    inits = [
        numpy_helper.from_array(
            rng.normal(0.0, 1.0 / np.sqrt(D), (D, H)).astype(np.float32), "W1"),
        numpy_helper.from_array(rng.normal(0.0, 0.1, (H,)).astype(np.float32), "b1"),
        numpy_helper.from_array(
            (0.8 + 0.4 * rng.random(H)).astype(np.float32), "g1"),
        numpy_helper.from_array(rng.normal(0.0, 0.1, (H,)).astype(np.float32), "beta1"),
        numpy_helper.from_array(
            rng.normal(0.0, 1.0 / np.sqrt(H), (H, H)).astype(np.float32), "W2"),
        numpy_helper.from_array(rng.normal(0.0, 0.1, (H,)).astype(np.float32), "b2"),
        numpy_helper.from_array(
            rng.normal(0.0, 1.0 / np.sqrt(H), (H, K)).astype(np.float32), "W3"),
        numpy_helper.from_array(rng.normal(0.0, 0.1, (K,)).astype(np.float32), "b3"),
        numpy_helper.from_array(np.array(0.5, np.float32), "c_half"),
        numpy_helper.from_array(np.array(1.0, np.float32), "c_one"),
        numpy_helper.from_array(np.array(np.sqrt(2.0), np.float32), "c_sqrt2"),
    ]
    nodes = (
        [helper.make_node("MatMul", ["x", "W1"], ["t1"]),
         helper.make_node("Add", ["t1", "b1"], ["h1"])]
        + gelu_subgraph("h1")
        + [helper.make_node("LayerNormalization", ["g_a", "g1", "beta1"], ["n1"],
                            axis=-1, epsilon=1e-5),
           helper.make_node("MatMul", ["n1", "W2"], ["t2"]),
           helper.make_node("Add", ["t2", "b2"], ["h2"])]
        + gelu_subgraph("h2")
        + [helper.make_node("MatMul", ["g_a1", "W3"], ["t3"]),
           helper.make_node("Add", ["t3", "b3"], ["logits"]),
           helper.make_node("Softmax", ["logits"], ["out"], axis=-1)]
    )
    # the second gelu subgraph reuses names; rewrite with a prefix
    nodes = []
    def gelu(x, p):
        return [
            helper.make_node("Div", [x, "c_sqrt2"], [p + "_d"]),
            helper.make_node("Erf", [p + "_d"], [p + "_e"]),
            helper.make_node("Add", [p + "_e", "c_one"], [p + "_e1"]),
            helper.make_node("Mul", [x, p + "_e1"], [p + "_m"]),
            helper.make_node("Mul", [p + "_m", "c_half"], [p + "_a"]),
        ]
    nodes = (
        [helper.make_node("MatMul", ["x", "W1"], ["t1"]),
         helper.make_node("Add", ["t1", "b1"], ["h1"])]
        + gelu("h1", "g1n")
        + [helper.make_node("LayerNormalization", ["g1n_a", "g1", "beta1"],
                            ["n1"], axis=-1, epsilon=1e-5),
           helper.make_node("MatMul", ["n1", "W2"], ["t2"]),
           helper.make_node("Add", ["t2", "b2"], ["h2"])]
        + gelu("h2", "g2n")
        + [helper.make_node("MatMul", ["g2n_a", "W3"], ["t3"]),
           helper.make_node("Add", ["t3", "b3"], ["logits"]),
           helper.make_node("Softmax", ["logits"], ["out"], axis=-1)]
    )
    graph = helper.make_graph(
        nodes, "calibration_net",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, ["B", D])],
        [helper.make_tensor_value_info("out", TensorProto.FLOAT, ["B", K])],
        inits)
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
    model.ir_version = 8
    onnx.checker.check_model(model)
    return model


def main():
    outdir = sys.argv[1]
    case_id = sys.argv[2]
    seed = int(sys.argv[3])
    D = int(sys.argv[4]) if len(sys.argv) > 4 else 12
    H = int(sys.argv[5]) if len(sys.argv) > 5 else 24
    K = int(sys.argv[6]) if len(sys.argv) > 6 else 5
    B = int(sys.argv[7]) if len(sys.argv) > 7 else 8

    rng = np.random.default_rng(seed)
    os.makedirs(outdir, exist_ok=True)
    model = build_graph(D, H, K, rng)
    onnx.save(model, os.path.join(outdir, "model.onnx"))

    x_fixed = rng.normal(0.0, 1.0, (B, D)).astype(np.float32)
    np.savez(os.path.join(outdir, "inputs_fixed.npz"), x=x_fixed)

    meta = {
        "case_id": case_id,
        "seed": seed,
        "in_dim": D,
        "hidden_dim": H,
        "out_dim": K,
        "fixed_batch": B,
        "random_batch": 16,
        "random_seed": seed + 9000,
        "atol": 1e-4,
        "rtol": 1e-3,
        "graph": ("h1=x@W1+b1; a1=0.5*h1*(1+erf(h1/sqrt(2))); "
                  "n1=LayerNorm(a1,g1,beta1,eps=1e-5); h2=n1@W2+b2; "
                  "a2=gelu(h2); o1=a2@W3+b3; out=softmax(o1,axis=-1)"),
    }
    with open(os.path.join(outdir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("%s: D=%d H=%d K=%d B=%d" % (case_id, D, H, K, B))


if __name__ == "__main__":
    main()
