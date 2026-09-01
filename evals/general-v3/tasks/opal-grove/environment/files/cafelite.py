#!/usr/bin/env python3
"""cafelite -- a tiny, prototxt-driven binary classifier trainer (CPU-only).

The Mica-Fjord... (no) -- this is the Opal-Grove training micro-framework.

It consumes a *solver* prototxt and two *network* prototxt files written in a
minimal caffe-like dialect, then trains the described network on a CSV dataset
with full-batch gradient descent.  It is intentionally strict: malformed
solver/network files, unsupported modes, or uncapped iteration counts are hard
errors (exit code 2).

Solver dialect (one ``key: value`` per line, ``#`` comments, blank lines ok)::

    solver_mode: CPU
    max_iter: 800
    base_lr: 0.5
    net: "train_net.prototxt"
    test_net: "test_net.prototxt"
    test_interval: 100

Required solver keys: ``solver_mode`` (must be CPU), ``max_iter`` (integer,
1..1500 inclusive), ``base_lr`` (float > 0), ``net`` / ``test_net`` (paths,
resolved relative to the solver file), ``test_interval`` (integer,
1..max_iter).

Network dialect (optional header lines, then ``layer { ... }`` blocks)::

    name: "opal_mlp"
    layer { name: "data"  type: "input" input_dim: 8 top: "x" }
    layer { name: "h1"    type: "dense" units: 16 bottom: "x" top: "h" activation: "relu" }
    layer { name: "out"   type: "dense" units: 1  bottom: "h" top: "p" activation: "sigmoid" }

Rules: exactly one ``input`` layer first (``input_dim`` 1..64, needs ``top``);
then one or more ``dense`` layers chained via ``bottom`` == previous ``top``
(``units`` 1..128, ``activation`` in {relu, sigmoid, tanh, none}); the final
dense layer must have ``units: 1`` and ``activation: "sigmoid"``.

CSV format: header row whose last column is ``label`` and whose feature columns
are numeric; one data row per line.  The feature count must equal the
network's ``input_dim``.

Run:
    python3 cafelite.py <solver.prototxt> --train <train.csv> --test <test.csv> --report <out.json>
"""
import csv
import json
import os
import re
import sys

import numpy as np

# full-batch GD can transiently saturate logits on some BLAS backends; the
# stable sigmoid keeps results exact, and we keep stderr clean of spurious
# floating-point chatter from platform BLAS quirks.
np.seterr(over="ignore", invalid="ignore", divide="ignore")

MAX_ITER_CAP = 1500
SEED = 20250607
ACTIVATIONS = ("relu", "sigmoid", "tanh", "none")


class PrototxtError(ValueError):
    pass


_INT_RE = re.compile(r"^[+-]?\d+$")
_FLOAT_RE = re.compile(r"^[+-]?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?$")


def _convert(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    if _INT_RE.match(value):
        return int(value)
    if _FLOAT_RE.match(value):
        return float(value)
    return value


_PAIR_RE = re.compile(r"(\w+)\s*:\s*(\"[^\"]*\"|'[^']*'|[^\s:#]+)")


def _parse_pairs(text, source, lineno):
    """Parse one or more 'key: value' pairs from a chunk of text."""
    fields = {}
    for key, value in _PAIR_RE.findall(text):
        fields[key] = _convert(value)
    stripped = text.strip()
    if stripped and not fields and ":" in stripped:
        raise PrototxtError("%s:%d: unparseable field text %r" % (source, lineno, stripped))
    return fields


def _parse_kv_lines(lines, source):
    fields = {}
    for lineno, raw in enumerate(lines, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if ":" not in line:
            raise PrototxtError("%s:%d: expected 'key: value', got %r" % (source, lineno, line))
        fields.update(_parse_pairs(line, source, lineno))
    return fields


def parse_solver(path):
    fields = _parse_kv_lines(open(path, "r", encoding="utf-8").read().splitlines(), path)
    for key in ("solver_mode", "max_iter", "base_lr", "net", "test_net", "test_interval"):
        if key not in fields:
            raise PrototxtError("solver %s: missing required key %r" % (path, key))
    mode = str(fields["solver_mode"]).strip().strip("\"'")
    if mode.upper() != "CPU":
        raise PrototxtError("solver %s: solver_mode must be CPU (got %r)" % (path, fields["solver_mode"]))
    mi = fields["max_iter"]
    if not isinstance(mi, int) or not (1 <= mi <= MAX_ITER_CAP):
        raise PrototxtError(
            "solver %s: max_iter must be an integer in [1, %d] (got %r)" % (path, MAX_ITER_CAP, mi)
        )
    lr = fields["base_lr"]
    if not isinstance(lr, (int, float)) or not (lr > 0):
        raise PrototxtError("solver %s: base_lr must be a positive number (got %r)" % (path, lr))
    ti = fields["test_interval"]
    if not isinstance(ti, int) or not (1 <= ti <= mi):
        raise PrototxtError("solver %s: test_interval must be an integer in [1, max_iter]" % path)
    fields["_dir"] = os.path.dirname(os.path.abspath(path))
    return fields


def parse_net(path):
    header = []
    layers = []
    current = None
    for lineno, raw in enumerate(open(path, "r", encoding="utf-8").read().splitlines(), 1):
        line = raw.split("#", 1)[0]
        # split the line around 'layer {' and '}' tokens so single-line and
        # multi-line layer blocks both parse
        parts = re.split(r"(layer\s*\{|\})", line)
        for part in parts:
            part = part.strip()
            if not part:
                continue
            if re.fullmatch(r"layer\s*\{", part):
                if current is not None:
                    raise PrototxtError("%s:%d: nested layer block" % (path, lineno))
                current = {}
                continue
            if part == "}":
                if current is None:
                    raise PrototxtError("%s:%d: unmatched '}'" % (path, lineno))
                layers.append(current)
                current = None
                continue
            pairs = _parse_pairs(part, path, lineno)
            if not pairs:
                raise PrototxtError("%s:%d: unparseable text %r" % (path, lineno, part))
            if current is None:
                header.append(pairs)
            else:
                current.update(pairs)
    if current is not None:
        raise PrototxtError("%s: unterminated layer block" % path)
    if len(layers) < 2:
        raise PrototxtError("%s: need one input layer plus at least one dense layer" % path)
    inp = layers[0]
    if inp.get("type") != "input":
        raise PrototxtError("%s: first layer must be type 'input'" % path)
    dim = inp.get("input_dim")
    if not isinstance(dim, int) or not (1 <= dim <= 64):
        raise PrototxtError("%s: input layer needs integer input_dim in [1, 64]" % path)
    if not inp.get("top"):
        raise PrototxtError("%s: input layer needs a top" % path)
    prev_top = inp["top"]
    for i, layer in enumerate(layers[1:], 1):
        if layer.get("type") != "dense":
            raise PrototxtError("%s: layer %d must be type 'dense'" % (path, i))
        units = layer.get("units")
        if not isinstance(units, int) or not (1 <= units <= 128):
            raise PrototxtError("%s: dense layer %d needs integer units in [1, 128]" % (path, i))
        if layer.get("bottom") != prev_top:
            raise PrototxtError(
                "%s: dense layer %d bottom %r does not match previous top %r"
                % (path, i, layer.get("bottom"), prev_top)
            )
        if not layer.get("top"):
            raise PrototxtError("%s: dense layer %d needs a top" % (path, i))
        act = str(layer.get("activation", "none")).strip().strip("\"'")
        if act not in ACTIVATIONS:
            raise PrototxtError("%s: dense layer %d bad activation %r" % (path, i, act))
        layer["activation"] = act
        prev_top = layer["top"]
    last = layers[-1]
    if last.get("units") != 1 or last.get("activation") != "sigmoid":
        raise PrototxtError("%s: final dense layer must be units: 1 with activation: sigmoid" % path)
    name = "net"
    if header:
        hf = {}
        for h in header:
            hf.update(h)
        name = str(hf.get("name", hf.get("net", name)))
    return {"name": name, "input_dim": dim, "layers": layers}


def _read_csv(path, input_dim):
    try:
        with open(path, "r", encoding="utf-8", newline="") as fh:
            rows = list(csv.reader(fh))
    except OSError as exc:
        raise PrototxtError("cannot read dataset %s: %s" % (path, exc))
    if not rows:
        raise PrototxtError("%s: empty CSV" % path)
    header = [h.strip() for h in rows[0]]
    if not header or header[-1] != "label":
        raise PrototxtError("%s: last header column must be 'label'" % path)
    X, y = [], []
    for lineno, row in enumerate(rows[1:], 2):
        if not row or all(not c.strip() for c in row):
            continue
        if len(row) != len(header):
            raise PrototxtError("%s:%d: expected %d fields, got %d" % (path, lineno, len(header), len(row)))
        try:
            feats = [float(c) for c in row[:-1]]
            label = float(row[-1])
        except ValueError:
            raise PrototxtError("%s:%d: non-numeric value" % (path, lineno))
        if len(feats) != input_dim:
            raise PrototxtError(
                "%s:%d: expected %d features, got %d" % (path, lineno, input_dim, len(feats))
            )
        if label not in (0.0, 1.0):
            raise PrototxtError("%s:%d: label must be 0 or 1" % (path, lineno))
        X.append(feats)
        y.append(label)
    if not X:
        raise PrototxtError("%s: no data rows" % path)
    return np.array(X, dtype=np.float64), np.array(y, dtype=np.float64)


def _sigmoid(z):
    """Numerically stable logistic function (no overflow warnings)."""
    out = np.empty_like(z)
    pos = z >= 0
    out[pos] = 1.0 / (1.0 + np.exp(-z[pos]))
    ez = np.exp(z[~pos])
    out[~pos] = ez / (1.0 + ez)
    return out


def _act_forward(name, a):
    if name == "relu":
        return np.maximum(a, 0.0)
    if name == "sigmoid":
        return _sigmoid(a)
    if name == "tanh":
        return np.tanh(a)
    return a


def _act_backward(name, a):
    if name == "relu":
        return (a > 0).astype(a.dtype)
    if name == "sigmoid":
        return a * (1.0 - a)
    if name == "tanh":
        return 1.0 - a * a
    return np.ones_like(a)


def build_model(net):
    rng = np.random.default_rng(SEED)
    params = []
    in_dim = net["input_dim"]
    for layer in net["layers"][1:]:
        units = layer["units"]
        W = rng.normal(0.0, 0.05, size=(in_dim, units))
        b = np.zeros(units)
        params.append({"W": W, "b": b, "act": layer["activation"]})
        in_dim = units
    return params


def forward(X, params):
    activations = [X]
    a = X
    for p in params:
        z = a @ p["W"] + p["b"]
        a = _act_forward(p["act"], z)
        activations.append(a)
    return activations


def predict_proba(X, params):
    return forward(X, params)[-1][:, 0]


def train(X, y, params, lr, max_iter):
    n = X.shape[0]
    for _ in range(max_iter):
        activations = forward(X, params)
        p = activations[-1][:, 0]
        delta = ((p - y) / n)[:, None]
        for i in range(len(params) - 1, -1, -1):
            a_prev = activations[i]
            params[i]["W"] -= lr * (a_prev.T @ delta)
            params[i]["b"] -= lr * delta.sum(axis=0)
            if i > 0:
                da = delta @ params[i]["W"].T
                delta = da * _act_backward(params[i - 1]["act"], activations[i])
    return params


def _bce(p, y):
    eps = 1e-12
    return float(-np.mean(y * np.log(p + eps) + (1.0 - y) * np.log(1.0 - p + eps)))


def _accuracy(p, y):
    return float(np.mean((p >= 0.5).astype(np.float64) == y))


def run(solver_path, train_csv, test_csv, report_path):
    solver = parse_solver(solver_path)
    train_net = parse_net(os.path.join(solver["_dir"], str(solver["net"])))
    test_net = parse_net(os.path.join(solver["_dir"], str(solver["test_net"])))
    if train_net["input_dim"] != test_net["input_dim"]:
        raise PrototxtError(
            "train net input_dim %d != test net input_dim %d"
            % (train_net["input_dim"], test_net["input_dim"])
        )
    Xtr, ytr = _read_csv(train_csv, train_net["input_dim"])
    Xte, yte = _read_csv(test_csv, train_net["input_dim"])

    params = build_model(train_net)
    params = train(Xtr, ytr, params, float(solver["base_lr"]), int(solver["max_iter"]))

    ptr = predict_proba(Xtr, params)
    pte = predict_proba(Xte, params)
    report = {
        "solver_mode": "CPU",
        "max_iter": int(solver["max_iter"]),
        "base_lr": round(float(solver["base_lr"]), 6),
        "test_interval": int(solver["test_interval"]),
        "train_rows": int(Xtr.shape[0]),
        "test_rows": int(Xte.shape[0]),
        "input_dim": int(train_net["input_dim"]),
        "final_train_loss": round(_bce(ptr, ytr), 6),
        "final_train_accuracy": round(_accuracy(ptr, ytr), 6),
        "final_test_accuracy": round(_accuracy(pte, yte), 6),
    }
    with open(report_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    print(
        "final_train_accuracy=%.4f final_test_accuracy=%.4f iterations=%d"
        % (report["final_train_accuracy"], report["final_test_accuracy"], report["max_iter"])
    )
    return report


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    solver_path = argv[1]
    opts = {"--train": None, "--test": None, "--report": None}
    i = 2
    while i < len(argv) - 1:
        key = argv[i]
        if key in opts and opts[key] is None:
            opts[key] = argv[i + 1]
            i += 2
        else:
            print("cafelite: bad argument %r" % key, file=sys.stderr)
            return 2
    if any(v is None for v in opts.values()):
        print("cafelite: --train, --test and --report are all required", file=sys.stderr)
        return 2
    try:
        run(solver_path, opts["--train"], opts["--test"], opts["--report"])
    except PrototxtError as exc:
        print("cafelite error: %s" % exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
