#!/usr/bin/env python3
"""Verifier helper for saffron-vine.

  python3 /tests/verify.py <casedir> <artifacts_dir>

Validates a LoRA-lifecycle artifact set against one fixture case:
  - the adapter directory is complete and self-sufficient (weights, config,
    feature spec) with shapes/config consistent with meta.json;
  - the merged state dict satisfies the merge equation exactly and changes
    no other tensor;
  - the adapter reloads onto the base and reproduces the merged model's
    outputs;
  - the merged model reaches the holdout accuracy target;
  - eval_metrics.json is consistent with recomputed numbers.
Prints "RESULT: PASS" on success.
"""
import json
import os
import sys

import numpy as np
import safetensors.torch as st
import torch
import torch.nn as nn


class Net(nn.Module):
    def __init__(self, vocab, embed, hidden, out, pad_id):
        super().__init__()
        self.emb = nn.Embedding(vocab, embed, padding_idx=pad_id)
        self.fc1 = nn.Linear(embed, hidden)
        self.fc2 = nn.Linear(hidden, hidden)
        self.head = nn.Linear(hidden, out)

    def forward(self, ids):
        z = self.emb(ids).mean(dim=1)
        t1 = torch.tanh(self.fc1(z))
        t2 = torch.tanh(self.fc2(t1))
        return self.head(t2)


def fail(msg):
    print("VERIFY-FAIL: %s" % msg)
    sys.exit(1)


def main():
    case, out = sys.argv[1], sys.argv[2]
    meta = json.load(open(os.path.join(case, "meta.json")))
    base = torch.load(os.path.join(case, "base_state.pt"), map_location="cpu")
    h = int(meta["hidden_dim"])
    r = int(meta["lora_rank"])
    alpha = float(meta["lora_alpha"])
    scale = alpha / r

    # ---- artifact presence --------------------------------------------------
    adir = os.path.join(out, "adapter")
    needed = [
        os.path.join(adir, "adapter_weights.safetensors"),
        os.path.join(adir, "adapter_config.json"),
        os.path.join(adir, "feature_spec.json"),
        os.path.join(out, "adapter_merged.pt"),
        os.path.join(out, "eval_metrics.json"),
    ]
    for p in needed:
        if not os.path.isfile(p):
            fail("missing artifact %s" % p)

    # ---- config -------------------------------------------------------------
    cfg = json.load(open(os.path.join(adir, "adapter_config.json")))
    for k in ("rank", "lora_alpha", "scale", "target_module",
              "base_architecture"):
        if k not in cfg:
            fail("adapter_config.json missing key %s" % k)
    if int(cfg["rank"]) != r:
        fail("config rank %s != meta lora_rank %d" % (cfg["rank"], r))
    if abs(float(cfg["lora_alpha"]) - alpha) > 1e-9:
        fail("config lora_alpha mismatch")
    if abs(float(cfg["scale"]) - scale) > 1e-9:
        fail("config scale != lora_alpha / rank")
    if cfg["target_module"] != meta["lora_target_module"]:
        fail("config target_module mismatch")
    ba = cfg["base_architecture"]
    for k in ("vocab_size", "embed_dim", "hidden_dim", "num_classes",
              "seq_len", "pad_id"):
        if k not in ba or int(ba[k]) != int(meta[k]):
            fail("base_architecture.%s mismatch" % k)

    # ---- feature spec (tokenizer) -------------------------------------------
    spec = json.load(open(os.path.join(adir, "feature_spec.json")))
    vocab_map = json.load(open(os.path.join(case, "vocab.json")))
    if spec.get("vocab") != vocab_map:
        fail("feature_spec vocab does not match the case tokenizer")
    if int(spec.get("seq_len", -1)) != int(meta["seq_len"]):
        fail("feature_spec seq_len mismatch")
    if int(spec.get("pad_id", -1)) != int(meta["pad_id"]):
        fail("feature_spec pad_id mismatch")

    # ---- adapter weights ----------------------------------------------------
    tensors = st.load_file(os.path.join(adir, "adapter_weights.safetensors"))
    if set(tensors.keys()) != {"lora_A", "lora_B"}:
        fail("safetensors keys %s != {lora_A, lora_B}" % sorted(tensors))
    A, B = tensors["lora_A"], tensors["lora_B"]
    if tuple(A.shape) != (r, h):
        fail("lora_A shape %s != (%d, %d)" % (tuple(A.shape), r, h))
    if tuple(B.shape) != (h, r):
        fail("lora_B shape %s != (%d, %d)" % (tuple(B.shape), h, r))
    if not (torch.isfinite(A).all() and torch.isfinite(B).all()):
        fail("adapter tensors contain non-finite values")

    # ---- merged state dict: keys + merge equation ---------------------------
    merged = torch.load(os.path.join(out, "adapter_merged.pt"),
                        map_location="cpu")
    if set(merged.keys()) != set(base.keys()):
        fail("merged keys != base keys (%s vs %s)"
             % (sorted(merged), sorted(base)))
    for k, v in base.items():
        if k == "fc2.weight":
            continue
        if not torch.equal(merged[k], v):
            fail("merged[%s] differs from base (only fc2.weight may change)"
                 % k)
    expect = base["fc2.weight"] + scale * (B @ A)
    if not torch.allclose(merged["fc2.weight"], expect, atol=1e-5, rtol=1e-5):
        fail("merge equation violated: max|dW - scale*B@A| = %.3e"
             % float((merged["fc2.weight"] - expect).abs().max()))

    # ---- adapter reload: reproduce merged outputs ---------------------------
    ids_te = torch.from_numpy(np.load(os.path.join(case, "test_ids.npy"))).long()
    y_te = np.load(os.path.join(case, "test_labels.npy"))

    torch.manual_seed(12345)
    probe = torch.randint(1, int(meta["vocab_size"]), (64, int(meta["seq_len"])))

    net = Net(meta["vocab_size"], meta["embed_dim"], meta["hidden_dim"],
              meta["num_classes"], meta["pad_id"])
    net.load_state_dict(merged)
    net.eval()
    with torch.no_grad():
        out_merged = net(probe)
        out_holdout = net(ids_te)

    # rebuild from base + adapter directory alone (reloadability)
    net2 = Net(meta["vocab_size"], meta["embed_dim"], meta["hidden_dim"],
               meta["num_classes"], meta["pad_id"])
    net2.load_state_dict(base)
    net2.eval()
    with torch.no_grad():
        z = net2.emb(probe).mean(dim=1)
        t1 = torch.tanh(net2.fc1(z))
        base_out = t1 @ net2.fc2.weight.T + net2.fc2.bias
        lora_out = base_out + scale * ((t1 @ A.T) @ B.T)
        out_reloaded = net2.head(torch.tanh(lora_out))
        # accuracy through the reloaded adapter path on the held-out split
        z = net2.emb(ids_te).mean(dim=1)
        t1 = torch.tanh(net2.fc1(z))
        base_out = t1 @ net2.fc2.weight.T + net2.fc2.bias
        lora_out = base_out + scale * ((t1 @ A.T) @ B.T)
        logits_te = net2.head(torch.tanh(lora_out))

    if not torch.allclose(out_merged, out_reloaded, atol=5e-2, rtol=2e-2):
        fail("reloaded adapter does not reproduce merged outputs "
             "(max diff %.3e)" % float((out_merged - out_reloaded).abs().max()))
    # prediction-level agreement: the two evaluation orders must make the
    # same call on (almost) every probe input despite float reassociation
    agree = float((out_merged.argmax(dim=1) == out_reloaded.argmax(dim=1))
                  .float().mean())
    if agree < 0.99:
        fail("reloaded adapter predictions disagree on %.1f%% of probe inputs"
             % (100 * (1 - agree)))

    acc = float((out_holdout.argmax(dim=1).numpy() == y_te).mean())
    target = float(meta["target_accuracy"])
    if acc < target:
        fail("merged holdout accuracy %.4f < target %.4f" % (acc, target))

    # ---- eval_metrics consistency -------------------------------------------
    m = json.load(open(os.path.join(out, "eval_metrics.json")))
    for k in ("case_id", "seed", "degraded_holdout_accuracy",
              "merged_holdout_accuracy", "target_accuracy", "threshold_pass"):
        if k not in m:
            fail("eval_metrics.json missing key %s" % k)
    if m["case_id"] != meta["case_id"]:
        fail("eval_metrics case_id mismatch")
    if int(m["seed"]) != int(meta["seed"]):
        fail("eval_metrics seed mismatch")
    if abs(float(m["merged_holdout_accuracy"]) - acc) > 5e-3:
        fail("eval_metrics merged accuracy %.4f != recomputed %.4f"
             % (float(m["merged_holdout_accuracy"]), acc))
    if abs(float(m["target_accuracy"]) - target) > 1e-9:
        fail("eval_metrics target_accuracy mismatch")
    if bool(m["threshold_pass"]) != (acc >= target):
        fail("eval_metrics threshold_pass inconsistent")
    # degraded accuracy must actually be degraded
    if float(m["degraded_holdout_accuracy"]) >= target:
        fail("degraded_holdout_accuracy should be below target")

    print("RESULT: PASS (merged holdout accuracy %.4f >= %.2f)"
          % (acc, target))


if __name__ == "__main__":
    main()
