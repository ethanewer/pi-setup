#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""prism-hearth verifier helper.

Usage:
    python3 verify.py <JOB.json> <OUTDIR> <EXPECTED_DIR>

Checks that /app/infer.py produced, in OUTDIR, output that (a) is structurally
valid, (b) reproduces the reference (golden) numbers stored under EXPECTED_DIR,
and (c) obeys documented constraints (AFAB ordering, per-microbatch budgets).
Reward=1 on all-pass, else 0.
"""
import json
import os
import sys
import math

JOB, OUT, EXP = sys.argv[1], sys.argv[2], sys.argv[3]


def _read(name):
    with open(os.path.join(OUT, name)) as f:
        if name.endswith(".txt"):
            return float(f.read().strip())
        return json.load(f)


def _exp(name):
    with open(os.path.join(EXP, name)) as f:
        if name.endswith(".txt"):
            return float(f.read().strip())
        return json.load(f)


def tol_float(a, b, rtol=1e-3, atol=1e-3):
    if a is None or b is None:
        return False
    if math.isinf(a) or math.isinf(b):
        return a == b
    return abs(a - b) <= (atol + rtol * abs(b))


with open(JOB) as f:
    job = json.load(f)

ok = True
failures = []


def chk(label, cond):
    global ok
    if not cond:
        ok = False
        failures.append(label)


# --- deliverables present in OUTDIR ---
for name in ["loss.txt", "batch_plan.json", "heads.json", "grad.json",
             "lm_head.json", "critical.json"]:
    chk("missing " + name, os.path.isfile(os.path.join(OUT, name)))

# --- loss ---
chk("loss value", tol_float(_read("loss.txt"), _exp("loss.txt"), rtol=2e-3, atol=2e-3))

# --- batch plan / AFAB / budgets ---
cap = int(job["batch_budget"])
win = int(job["window"])


def greedy_groups():
    groups, cur, csp, cc = [], [], 0, 0
    for i, r in enumerate(job["requests"]):
        sp = int(r.get("span", 1))
        if cur and (csp + sp > win or cc >= cap):
            groups.append(cur)
            cur, csp, cc = [], 0, 0
        cur.append(i)
        csp += sp
        cc += 1
    if cur:
        groups.append(cur)
    return groups


groups = greedy_groups()
n_mb = len(groups)
bp = _read("batch_plan.json")
chk("microbatches pack", bp.get("microbatches") == groups)
chk("n_microbatches", bp.get("n_microbatches") == n_mb)
chk("batch_satisfied", bool(bp.get("batch_satisfied")))

order = [e[0] for e in bp.get("order", []) if isinstance(e, str) and e]
chk("AFAB order", order == ["F"] * n_mb + ["B"] * n_mb)
if "B" in order:
    fb = order.index("B")
    chk("no F after B", all(c != "F" for c in order[fb:]))
chk("group sizes within batch cap", all(len(g) <= cap for g in groups))

# --- heads ---
heads = _read("heads.json")
chk("policy dim", len(heads.get("policy_logits", [])) == 10)
probs = heads.get("outcome_probs", [])
chk("outcome dim", len(probs) == 3)
chk("outcome sums 1", abs(sum(probs) - 1.0) < 1e-4)
chk("mil dim", heads.get("mil_logits_dim") == 10)
chk("attention len == bag size",
    heads.get("attention_len") == heads.get("bag_size")
    and heads.get("attention_len") == len(heads.get("attention", [])))

exp_heads = _exp("heads.json")
chk("outcome golden", all(tol_float(a, b, 2e-2, 2e-2)
                          for a, b in zip(probs, exp_heads["outcome_probs"])))
pol, ep = heads.get("policy_logits", []), exp_heads["policy_logits"]
chk("policy golden", len(pol) == len(ep) and all(tol_float(a, b, 2e-2, 2e-2)
                                                 for a, b in zip(pol, ep)))

# --- gradient accumulation ---
grad, eg = _read("grad.json"), _exp("grad.json")
for k in ("W2_norm", "W1_norm"):
    chk("grad " + k, tol_float(grad.get(k, 0), eg[k], rtol=2e-2, atol=2e-2))

# --- causal LM + tokenizer ---
lm, exp_lm = _read("lm_head.json"), _exp("lm_head.json")
chk("lm_loaded", bool(lm.get("lm_loaded")))
chk("tokenizer_loaded", bool(lm.get("tokenizer_loaded")))
chk("vocab_size", lm.get("vocab_size") == exp_lm["vocab_size"])
chk("lm_ce", tol_float(float(lm.get("loss_ce") or 0.0), float(exp_lm["loss_ce"]),
                       rtol=1e-3, atol=1e-3))

# --- weight artifact shape-preservation (current asset) ---
try:
    import torch
    import pickle
    sdchk = torch.load("/app/weights/hearth_net.pt", map_location="cpu")
    chk("W1 shape", tuple(sdchk["enc.weight"].shape) == (10, 784))
    chk("W2 shape", tuple(sdchk["act.weight"].shape) == (10, 10))
    chk("biases", tuple(sdchk["enc.bias"].shape) == (10,)
        and tuple(sdchk["act.bias"].shape) == (10,))
except Exception:
    chk("asset shape load", False)

print("verify_ok=%d fails=%d" % (ok, len(failures)))
for f_ in failures:
    print("   FAIL:", f_)
sys.exit(0 if ok else 1)