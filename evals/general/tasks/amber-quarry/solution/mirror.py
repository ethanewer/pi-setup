#!/usr/bin/env python3
"""
amber-quarry: mirror a calibration ONNX graph in pure numpy.

  python3 mirror.py <model.onnx> <inputs.npz> <output.npz>

Loads the graph with the `onnx` package (PARSING ONLY — executing the graph
with onnxruntime is forbidden), evaluates it with numpy, and writes the
softmax outputs under key "out" into <output.npz>.

Supported ops (the documented calibration graph uses exactly these):
  MatMul, Add, Mul, Div, Erf, LayerNormalization, Softmax
Initializers supply the weights; "x" is the graph input.
"""
import json
import math
import sys

import numpy as np
import onnx
from onnx import numpy_helper

erf_vec = np.vectorize(math.erf, otypes=[np.float64])


def _attr(node, name, default=None):
    for a in node.attribute:
        if a.name == name:
            if a.type == onnx.AttributeProto.FLOAT:
                return a.f
            if a.type == onnx.AttributeProto.INT:
                return a.i
            return helper_get(a)
    return default


def helper_get(a):
    raise ValueError("unsupported attribute type %d" % a.type)


def layernorm(x, scale, bias, axis, eps):
    x64 = x.astype(np.float64)
    mu = x64.mean(axis=axis, keepdims=True)
    var = x64.var(axis=axis, keepdims=True)
    norm = (x64 - mu) / np.sqrt(var + eps)
    return (norm * scale.astype(np.float64)
            + bias.astype(np.float64)).astype(np.float32)


def softmax(x, axis):
    x64 = x.astype(np.float64)
    m = x64.max(axis=axis, keepdims=True)
    e = np.exp(x64 - m)
    return (e / e.sum(axis=axis, keepdims=True)).astype(np.float32)


def main():
    model_path, inputs_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    model = onnx.load(model_path)
    graph = model.graph

    tensors = {}
    for init in graph.initializer:
        tensors[init.name] = numpy_helper.to_array(init)

    feed = dict(np.load(inputs_path))
    if "x" not in feed:
        raise ValueError("inputs file must contain key 'x'")
    tensors["x"] = np.asarray(feed["x"], dtype=np.float32)

    for node in graph.node:
        op = node.op_type
        ins = [tensors[n] for n in node.input]
        if op == "MatMul":
            res = ins[0].astype(np.float64) @ ins[1].astype(np.float64)
            tensors[node.output[0]] = res.astype(np.float32)
        elif op == "Add":
            tensors[node.output[0]] = (ins[0] + ins[1]).astype(np.float32)
        elif op == "Mul":
            tensors[node.output[0]] = (ins[0] * ins[1]).astype(np.float32)
        elif op == "Div":
            tensors[node.output[0]] = (ins[0] / ins[1]).astype(np.float32)
        elif op == "Erf":
            res = erf_vec(ins[0].astype(np.float64))
            tensors[node.output[0]] = res.astype(np.float32)
        elif op == "LayerNormalization":
            axis = _attr(node, "axis", -1)
            eps = _attr(node, "epsilon", 1e-5)
            tensors[node.output[0]] = layernorm(ins[0], ins[1], ins[2],
                                                axis, eps)
        elif op == "Softmax":
            axis = _attr(node, "axis", -1)
            tensors[node.output[0]] = softmax(ins[0], axis)
        else:
            raise ValueError("unsupported op %s" % op)

    out_name = graph.output[0].name
    np.savez(out_path, out=tensors[out_name].astype(np.float32))
    print("wrote %s: shape %s" % (out_path, tensors[out_name].shape))


if __name__ == "__main__":
    main()
