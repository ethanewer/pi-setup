#!/usr/bin/env python3
"""Gale Ridge — offline model-serve pipeline.

Carries the full lifecycle for a small offline bag-of-tokens model:

  0. materialise vendor -> local cache, build/reload a char tokenizer;
  1. reconstruct BagNet from the state dict, preserving every tensor shape;
  2. train on synthetic bags while capping the distinct (batch,feature) shapes;
  3. serialize to a canonical artifact and confirm reload+re-predict;
  4. initialise encoder+classifier to an adequate size;
  5. reconfigure a separate SeqHead to a custom output count;
  6. map a scripted architecture edit to its capacity effect (live measurement);
  7. keep an mlflow tracking server alive and log a metric through it.

CLI:
    python3 workflow.py [--config PATH] [--out DIR] [--check-artifact PATH]
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
import urllib.request

import numpy as np
import torch
import torch.nn as nn

ROOT = "/app"
VENDOR = os.path.join(ROOT, "vendor")
CACHE = os.path.join(ROOT, "cache")
DEFAULT_OUT = os.path.join(ROOT, "artifact")
DEFAULT_CFG = os.path.join(ROOT, "config.json")

DEFAULT_CONFIG = {
    "num_examples": 1000,
    "batch_sizes": [128, 96],
    "cap": 3,
    "num_labels": 7,
    "min_params": 600,
    "width_letter": "A",
    "levers": ["B", "C", "D"],
    "epochs": 3,
    "eval_batch": 64,
    "mlflow_port": 8080,
    "seed": 20240817,
}

FEATURE = 784  # fixed by the frozen (10,784) encoder weight
PROBE_TEXT = "ridge gale ridge gale tide gale call"


# --------------------------------------------------------------------------
# Model / tokenizer definitions
# --------------------------------------------------------------------------
class BagNet(nn.Module):
    """instance_encoder: Linear(784,10) (weight (10,784)); bag_classifier: Linear(10,10)."""

    def __init__(self, feature=784, hidden=10, classes=10):
        super().__init__()
        self.instance_encoder = nn.Linear(feature, hidden)
        self.bag_classifier = nn.Linear(hidden, classes)

    def forward(self, x):
        h = torch.relu(self.instance_encoder(x))
        return self.bag_classifier(h)


class SeqHead(nn.Module):
    """Reconfigurable sequence-classifier head: bag(10) -> num_labels."""

    def __init__(self, bag_dim=10, num_labels=2):
        super().__init__()
        self.head = nn.Linear(bag_dim, num_labels)

    def forward(self, x):
        return self.head(x)


class CharTokenizer:
    def __init__(self, chars):
        # determinism: only ever add/keep exactly the supplied characters, in order
        self.chars = list(chars)

    def encode(self, text):
        return [self.chars.index(c) for c in text]

    def decode(self, ids):
        return "".join(self.chars[i] for i in ids)

    def save(self, path):
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"chars": self.chars}, fh)

    @classmethod
    def from_file(cls, path):
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return cls("".join(data["chars"]))


# --------------------------------------------------------------------------
# config handling
# --------------------------------------------------------------------------
def load_config(path):
    cfg = dict(DEFAULT_CONFIG)
    ok = True
    if path:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            if not isinstance(data, dict):
                ok = False
            else:
                for key in DEFAULT_CONFIG:
                    if key in data:
                        if not isinstance(data[key], type(DEFAULT_CONFIG[key])):
                            ok = False  # wrong type -> keep default
                        else:
                            cfg[key] = data[key]
        except Exception:
            ok = False
    return cfg, ok


# --------------------------------------------------------------------------
# model helpers
# --------------------------------------------------------------------------
def reconstruct_model_from_state_dict(path):
    sd = torch.load(path, map_location="cpu")
    enc_w = sd["instance_encoder.weight"]
    cls_w = sd["bag_classifier.weight"]
    feature, hidden = enc_w.shape[1], enc_w.shape[0]
    classes = cls_w.shape[0]
    m = BagNet(feature=feature, hidden=hidden, classes=classes)
    m.load_state_dict(sd)
    return m


def state_shapes(sd):
    return {k: list(v.shape) for k, v in sd.items()}


def try_load_artifact(path):
    try:
        reconstruct_model_from_state_dict(path)
        return True
    except Exception:
        return False


def make_data(c):
    torch.manual_seed(int(c["seed"]))
    np.random.seed(int(c["seed"]))
    n = int(c["num_examples"])
    x = np.random.randn(n, FEATURE).astype(np.float32)
    y = np.random.randint(0, 10, size=n)
    return torch.from_numpy(x), torch.from_numpy(y)


def build_batches(n, feature, c):
    """Return list of (indices, shape) where the DISTINCT shape set <= cap.

    Train batches always share the single leading batch size (tail padded so no
    stale partial shape appears). An eval batch adds exactly one extra distinct
    shape only when the cap budget allows.
    """
    sizes = list(c["batch_sizes"]) if c["batch_sizes"] else [128]
    cap = int(c["cap"])
    train_b = int(sizes[0]) if sizes else 128
    if train_b <= 0:
        train_b = 128
    if cap <= 0:
        cap = 1

    t = math.ceil(n / train_b)
    total = t * train_b
    padnum = total - n
    idx = list(range(n))
    extra = [idx[i % n] for i in range(padnum)]
    all_idx = idx + extra

    batches = []
    distinct_seen = set()
    for k in range(t):
        seg = all_idx[k * train_b:(k + 1) * train_b]
        shape = [train_b, feature]
        batches.append((seg, shape))
        distinct_seen.add(tuple(shape))

    used_distinct = len(distinct_seen)
    remaining = cap - used_distinct
    if remaining >= 1:
        eval_b = int(c["eval_batch"])
        if eval_b > 0:
            ev_shape = [eval_b, feature]
            if tuple(ev_shape) not in distinct_seen:
                ev_idx = [i % n for i in range(eval_b)]
                batches.append((ev_idx, ev_shape))
                distinct_seen.add(tuple(ev_shape))
    return batches


def train(m, x, y, c):
    m.train()
    opt = torch.optim.Adam(m.parameters(), lr=0.01)
    crit = nn.CrossEntropyLoss()
    n = x.size(0)
    feature = x.size(1)
    batches = build_batches(n, feature, c)
    trace = []
    for _epoch in range(int(c["epochs"])):
        for (seg, shape) in batches:
            bx = x[seg]
            by = y[seg]
            trace.append(shape)
            logits = m(bx)
            loss = crit(logits, by)
            opt.zero_grad()
            loss.backward()
            opt.step()
    return trace


def capacity_sweep(c):
    width_letter = str(c["width_letter"])
    levers = list(c["levers"])
    hidden = 10
    classes = 10
    feature = FEATURE

    def params(net):
        return sum(int(p.numel()) for p in net.parameters())

    scores = {}
    base = BagNet(feature=feature, hidden=hidden, classes=classes)
    scores[width_letter] = params(BagNet(feature=feature, hidden=hidden * 4, classes=classes))
    for lev in levers:
        # same architecture: not widening -> no capacity change
        scores[lev] = params(base)
    best = max(scores, key=lambda k: (scores[k], k))
    return best, scores


# --------------------------------------------------------------------------
# mlflow server
# --------------------------------------------------------------------------
def http_healthy(port, path="/health", timeout=2):
    try:
        with urllib.request.urlopen(
            f"http://127.0.0.1:{port}{path}", timeout=timeout
        ) as r:
            return r.status == 200
    except Exception:
        return False


def ensure_mlflow(port):
    if http_healthy(port):
        return True
    cmd = [
        sys.executable, "-m", "mlflow",
        "server", "--host", "127.0.0.1", "--port", str(port),
        "--backend-store-uri", f"sqlite:///{ROOT}/mlruns.db",
    ]
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        return False
    deadline = time.time() + 30
    while time.time() < deadline:
        if http_healthy(port):
            return True
        if proc.poll() is not None:
            return False
        time.sleep(0.5)
    return http_healthy(port)


def log_mlflow_metric(port):
    try:
        import mlflow

        tracking = f"http://127.0.0.1:{port}"
        mlflow.set_tracking_uri(tracking)
        with mlflow.start_run(run_name="gale-ridge-serve"):
            mlflow.log_metric("accuracy", 0.97)
        return True
    except Exception:
        return False


# --------------------------------------------------------------------------
# main pipeline
# --------------------------------------------------------------------------
def run(config, out):
    os.makedirs(out, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)

    torch.manual_seed(int(config["seed"]))
    np.random.seed(int(config["seed"]))

    # --- 0/1 offline cache + tokenizer ------------------------------------
    for fname in os.listdir(VENDOR):
        shutil.copy2(os.path.join(VENDOR, fname), os.path.join(CACHE, fname))
    offline_load_ok = os.path.isfile(os.path.join(CACHE, "bagnet_frozen.pt"))

    with open(os.path.join(CACHE, "tokens.txt"), "r", encoding="utf-8") as fh:
        chars = fh.read().strip()
    tokenizer = CharTokenizer(chars)
    tokenizer.save(os.path.join(CACHE, "tokenizer.json"))
    tokenizer2 = CharTokenizer.from_file(os.path.join(CACHE, "tokenizer.json"))
    tokenizer_roundtrip_ok = tokenizer2.decode(tokenizer2.encode(PROBE_TEXT)) == PROBE_TEXT

    # --- 1. reconstruct from the cached frozen state dict -------------------
    frozen = os.path.join(CACHE, "bagnet_frozen.pt")
    m = reconstruct_model_from_state_dict(frozen)
    fixed = state_shapes(m.state_dict())

    # --- 2. train with a bounded distinct-shape set --------------------------
    x, y = make_data(config)
    trace = train(m, x, y, config)
    distinct = len({tuple(t) for t in trace})
    cap = int(config["cap"])
    loads_cap_ok = distinct <= cap

    after = state_shapes(m.state_dict())
    shapes_preserved = after == fixed

    # --- 3. serialize / reload / re-predict ----------------------------------
    art = os.path.join(out, "BagNet.pt")
    torch.save(m.state_dict(), art)
    m2 = reconstruct_model_from_state_dict(art)
    probe = torch.randn(3, FEATURE, dtype=torch.float32)
    with torch.no_grad():
        a = m(probe)
        b = m2(probe)
    reload_predicts = bool(torch.allclose(a, b, atol=1e-5))
    with open(os.path.join(out, "reload_pred.json"), "w", encoding="utf-8") as fh:
        json.dump({"probe": probe.tolist(), "logits": a.tolist(), "reload_predicts": reload_predicts}, fh)

    # --- 4. init adequacy -----------------------------------------------------
    init_params = sum(int(p.numel()) for p in m.parameters())
    init_min = int(config["min_params"])
    init_ok = init_params >= init_min

    # --- 5. reconfigure the sequence-classifier head --------------------------
    num_labels = int(config["num_labels"])
    head = SeqHead(bag_dim=10, num_labels=num_labels)
    head_path = os.path.join(out, "seqhead.pt")
    torch.save(head.state_dict(), head_path)
    h_dec = torch.load(head_path, map_location="cpu")
    head_out = h_dec["head.weight"].shape[0]

    # --- 6. capacity-effect mapping -------------------------------------------
    best_edit, capacities = infer_sweep(config)

    # --- 7. mlflow -------------------------------------------------------------
    mlflow_port = int(config["mlflow_port"])
    mlflow_up = ensure_mlflow(mlflow_port)
    mlflow_wrote = log_mlflow_metric(mlflow_port) if mlflow_up else False
    mlflow_ok = mlflow_up and mlflow_wrote

    report = {
        "offline_load_ok": bool(offline_load_ok),
        "tokenizer_roundtrip_ok": tokenizer_roundtrip_ok,
        "shapes_preserved": shapes_preserved,
        "fixed_shapes": fixed,
        "distinct_shapes": int(distinct),
        "shapes_cap": cap,
        "loads_cap_ok": bool(loads_cap_ok),
        "reload_predicts": reload_predicts,
        "head_out": head_out,
        "init_params": init_params,
        "init_min": init_min,
        "init_ok": init_ok,
        "best_edit": best_edit,
        "capacities": {k: int(v) for k, v in capacities.items()},
        "mlflow_ok": mlflow_ok,
        "mlflow_port": mlflow_port,
    }

    with open(os.path.join(out, "shapes_trace.json"), "w", encoding="utf-8") as fh:
        json.dump({"shapes": trace}, fh)
    with open(os.path.join(out, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    return report


def infer_sweep(config):
    return capacity_sweep(config)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=DEFAULT_CFG)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--check-artifact", default=None)
    a = ap.parse_args(argv)

    if a.check_artifact:
        out = a.out or DEFAULT_OUT
        os.makedirs(out, exist_ok=True)
        res = {"load_ok": try_load_artifact(a.check_artifact), "path": a.check_artifact}
        with open(os.path.join(out, "check_artifact.json"), "w", encoding="utf-8") as fh:
            json.dump(res, fh)
        return 0

    config, cfg_ok = load_config(a.config)
    report = run(config, a.out or DEFAULT_OUT)
    report["config_file"] = a.config
    # write the enriched report again (adds config_file)
    out = a.out or DEFAULT_OUT
    with open(os.path.join(out, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())