#!/usr/bin/env python3
"""raven-v1 inference adapter.

A runnable CLI that drives the full self-play inference close-out:

  lm      : tokenize + causal-LM forward; report the mean loss over micro-batches
  head    : reload the local causal LM and reconfigure its classification head to
            a custom class count, then save the reconfigured model
  milp    : bag multiple-instance-learning forward (encoder + attention gate +
            classifier) -> bag logits + unit-sum attention
  wdl     : policy/WDL head forward -> legal-move logits + post-softmax outcome vec
  batch   : bundle a streaming request log into aligned micro-batches under a
            latency / batch-size budget -> plan JSON
  workflow: end-to-end default run over /app/input -> /app/loss.txt,
            /app/batch_plan.json, and /app/out/*.json

All engine weights are read from the committed /app/engine checkpoint; every
sub-command is deterministic for a fixed input.
"""
import argparse, json, math, os, sys

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

CFG = json.load(open("/app/config.json"))
MODEL_DIR = CFG["model_dir"]
TOK_DIR = CFG["tokenizer_dir"]
FEAT = int(CFG["feat_dim"])
ENC = int(CFG["encoder_hidden"])
MIC = int(CFG["milp_classes"])
WO = int(CFG["wdl_outcomes"])
MB = int(CFG["lm_mb"])
BASELINE = CFG["baseline_sha"]


# ------------------------------------------------------------------------- LM
def _lm_load():
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(TOK_DIR, local_files_only=True, use_fast=True)
    model = AutoModelForCausalLM.from_pretrained(MODEL_DIR, local_files_only=True)
    model.eval()
    return tok, model


def lm_losses(lines, mb):
    """Per-line CE loss, then average over micro-batches of size `mb`.

    The reference contract: split the stream into consecutive micro-batches of
    `mb` lines (last micro-batch may be shorter); the reported loss is the
    (equal-weighted) mean of the per-micro-batch mean losses.
    """
    tok, model = _lm_load()
    per = []
    with torch.no_grad():
        for ln in lines:
            ln = ln.strip()
            if not ln:
                continue
            enc = tok(ln, return_tensors="pt", truncation=True, max_length=256)
            ids = enc["input_ids"]
            out = model(ids, labels=ids)
            per.append(float(out.loss.item()))
    if not per:
        return 0.0
    mb_means = []
    for i in range(0, len(per), mb):
        chunk = per[i:i + mb]
        mb_means.append(float(np.mean(chunk)))
    return float(np.mean(mb_means))


def cmd_lm(args):
    lines = [l for l in open(args.input).read().splitlines()]
    mb = args.mb if args.mb else MB
    loss = lm_losses(lines, mb)
    with open(args.output, "w") as fh:
        fh.write(f"{loss:.4f}\n")
    print(f"lm loss={loss:.4f} lines={len(lines)} for {args.output}")


# ---------------------------------------------------------------------------- head
def cmd_head(args):
    from transformers import AutoModelForSequenceClassification
    count = int(args.count)
    clf = AutoModelForSequenceClassification.from_pretrained(
        MODEL_DIR, num_labels=count, local_files_only=True,
        ignore_mismatched_sizes=True)
    os.makedirs(args.output, exist_ok=True)
    clf.save_pretrained(args.output)
    got = int(getattr(clf.config, "num_labels", -1))
    print(f"[head] reconfigured to num_labels={got} at {args.output}")
    if got != count:
        raise SystemExit(f"head count mismatch: config={got} expected={count}")


# ----------------------------------------------------------------------- bag-MIL
class BagNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.enc = nn.Linear(FEAT, ENC)
        self.gate = nn.Linear(ENC, 1)
        self.clf = nn.Linear(ENC, MIC)

    def forward(self, X):
        if X.shape[0] == 0:
            logits = torch.zeros(MIC)
            attn = torch.zeros(0)
            return logits, attn
        h = F.relu(self.enc(X))            # (T, ENC)
        a = torch.softmax(self.gate(h), dim=0)   # (T, 1)
        a = a.squeeze(1)                   # (T,)
        bag = (a.unsqueeze(1) * h).sum(0)  # (ENC,)
        logits = self.clf(bag)             # (MIC,)
        return logits, a


def cmd_milp(args):
    z = np.load(args.input)
    X = np.asarray(z["X"], dtype=np.float32)
    net = BagNet()
    net.eval()
    with torch.no_grad():
        lg, at = net(torch.from_numpy(X))
    out = {
        "logits": [round(float(v), 6) for v in lg.tolist()],
        "attention": [round(float(v), 6) for v in at.tolist()],
        "instance_count": int(X.shape[0]),
    }
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w") as fh:
        json.dump(out, fh)
    print(f"[milp] instances={X.shape[0]} -> {args.output}")


# ------------------------------------------------------------------------- WDL
class WDLHead(nn.Module):
    def __init__(self):
        super().__init__()
        self.enc = nn.Linear(FEAT, ENC)
        self.legal = nn.Linear(ENC, 1)
        self.out = nn.Linear(ENC, WO)

    def forward(self, X):
        if X.shape[0] == 0:
            leg = torch.zeros(0)
            probs = torch.full((WO,), 1.0 / WO)
            return leg, probs
        h = F.relu(self.enc(X))                  # (k, ENC)
        leg = self.legal(h).squeeze(1)           # (k,)
        pooled = h.mean(0)                        # (ENC,)
        probs = F.softmax(self.out(pooled), dim=0)  # (WO,)
        return leg, probs


def cmd_wdl(args):
    z = np.load(args.input)
    X = np.asarray(z["X"], dtype=np.float32)
    head = WDLHead()
    head.eval()
    with torch.no_grad():
        leg, probs = head(torch.from_numpy(X))
    out = {
        "legal_logits": [round(float(v), 6) for v in leg.tolist()],
        "outcome_probs": [round(float(v), 6) for v in probs.tolist()],
        "outcomes": WO,
        "legal_count": int(X.shape[0]),
    }
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w") as fh:
        json.dump(out, fh)
    print(f"[wdl] legal={X.shape[0]} -> {args.output}")


# ----------------------------------------------------------------------- batching
def cmd_batch(args):
    data = json.load(open(args.input))
    budget = data["budget"]
    reqs = data["requests"]
    batch_tok = int(budget["batch_tok"])
    win = int(budget["window"])
    gran = int(budget["granularity"])
    max_win = int(budget["windows"])

    # phase 1: split the stream into windows (each window's token sum <= win)
    win_reqs = []
    cur, ct = [], 0
    for r in reqs:
        if cur and ct + int(r["tokens"]) > win:
            win_reqs.append(cur)
            cur, ct = [], 0
        cur.append(r)
        ct += int(r["tokens"])
    if cur:
        win_reqs.append(cur)

    # phase 2: within each window bundle requests into aligned micro-batches
    windows = []
    for wi, wreq in enumerate(win_reqs):
        mbs = []
        m, mt = [], 0
        for r in wreq:
            rt = int(r["tokens"])
            if m and mt + rt > batch_tok:
                mbs.append({"batch_id": f"w{wi}-m{len(mbs)}",
                            "requests": [x["id"] for x in m], "tokens": mt})
                m, mt = [], 0
            m.append(r)
            mt += rt
        if m:
            mbs.append({"batch_id": f"w{wi}-m{len(mbs)}",
                        "requests": [x["id"] for x in m], "tokens": mt})
        wtot = sum(b["tokens"] for b in mbs)
        windows.append({"window_id": f"w{wi}", "tokens": wtot,
                        "microbatches": mbs})

    plan = {"budget": budget, "windows": windows}
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w") as fh:
        json.dump(plan, fh, indent=2)
    total = len(reqs)
    print(f"[batch] requests={total} windows={len(windows)} -> {args.output}")


# --------------------------------------------------------------------- workflow
def cmd_workflow(args):
    mb = args.mb if args.mb else MB
    loss = lm_losses(open("/app/input/probe.txt").read().splitlines(), mb)
    with open("/app/loss.txt", "w") as fh:
        fh.write(f"{loss:.4f}\n")
    cmd_batch(argparse.Namespace(input="/app/input/requests.json",
                                 output="/app/batch_plan.json"))
    cmd_milp(argparse.Namespace(input="/app/input/bag.npz",
                                output="/app/out/milp.json"))
    cmd_wdl(argparse.Namespace(input="/app/input/state.npz",
                               output="/app/out/wdl.json"))
    hc = json.load(open("/app/input/headcount.json"))["count"]
    cmd_head(argparse.Namespace(count=hc, output="/app/out/head"))


def main():
    p = argparse.ArgumentParser(prog="infer.py")
    sub = p.add_subparsers(required=True)

    s = sub.add_parser("lm"); s.add_argument("--input", required=True)
    s.add_argument("--output", required=True); s.add_argument("--mb", type=int, default=0)
    s.set_defaults(func=cmd_lm, name="lm")

    s = sub.add_parser("head"); s.add_argument("--count", required=True)
    s.add_argument("--output", required=True); s.set_defaults(func=cmd_head, name="head")

    s = sub.add_parser("milp"); s.add_argument("--input", required=True)
    s.add_argument("--output", required=True); s.set_defaults(func=cmd_milp, name="milp")

    s = sub.add_parser("wdl"); s.add_argument("--input", required=True)
    s.add_argument("--output", required=True); s.set_defaults(func=cmd_wdl, name="wdl")

    s = sub.add_parser("batch"); s.add_argument("--input", required=True)
    s.add_argument("--output", required=True); s.set_defaults(func=cmd_batch, name="batch")

    s = sub.add_parser("workflow"); s.add_argument("--mb", type=int, default=0)
    s.set_defaults(func=cmd_workflow, name="workflow")

    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()