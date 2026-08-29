#!/usr/bin/env python3
"""Independent verifier for raven-mantle.

Re-derives reference behavior from the committed /app/engine checkpoint and the
shipped fixtures, runs every /app/infer.py mode on the default fixtures and on
every hidden scenario, confirms the engine weights are byte-for-byte unchanged,
and writes a numeric reward to /logs/verifier/reward.txt.
"""
import hashlib, json, os, subprocess, sys
import numpy as np
import torch

CFG = json.load(open("/app/config.json"))
MODEL_DIR = CFG["model_dir"]
TOK_DIR = CFG["tokenizer_dir"]
FEAT = int(CFG["feat_dim"]); ENC = int(CFG["encoder_hidden"])
MIC = int(CFG["milp_classes"]); WO = int(CFG["wdl_outcomes"])
MB = int(CFG["lm_mb"]); BASELINE = CFG["baseline_sha"]
FLOOR = 9.0
TOL = 1e-3
REWARD = "/logs/verifier/reward.txt"

from transformers import AutoModelForCausalLM, AutoTokenizer
_TOK = AutoTokenizer.from_pretrained(TOK_DIR, local_files_only=True, use_fast=True)
_MODEL = AutoModelForCausalLM.from_pretrained(MODEL_DIR, local_files_only=True)
_MODEL.eval()

FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)
        print("  FAIL:", msg)
    else:
        print("  ok:", msg)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def reference_losses(lines):
    per = []
    with torch.no_grad():
        for ln in lines:
            ln = ln.strip()
            if not ln:
                continue
            enc = _TOK(ln, return_tensors="pt", truncation=True, max_length=256)
            ids = enc["input_ids"]
            out = _MODEL(ids, labels=ids)
            per.append(float(out.loss.item()))
    if not per:
        return 0.0
    mb_means = [float(np.mean(per[i:i + MB])) for i in range(0, len(per), MB)]
    return float(np.mean(mb_means))


def check_engine_integrity():
    man = {}
    for ln in open(BASELINE):
        h, rel = ln.split("  ", 1)
        man[rel.strip()] = h
    cur = {}
    for root, _, files in os.walk("/app/engine"):
        for f in sorted(files):
            p = os.path.join(root, f)
            if p.endswith(".baseline.sha256") or os.path.islink(p):
                continue
            rel = os.path.relpath(p, "/app/engine")
            cur[rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()
    if set(man) != set(cur):
        check(False, "engine file set changed")
        return
    dif = [k for k in man if man[k] != cur[k]]
    check(not dif, f"engine weights byte-identical ({len(man)} files)")


def check_lm(probe, outfile):
    if not os.path.isfile(outfile):
        check(False, f"missing lm output {outfile}")
        return
    got = float(open(outfile).read().split()[0])
    ref = reference_losses([l for l in open(probe).read().splitlines()])
    check(abs(got - ref) <= TOL, f"lm loss matches reference ({got:.4f} vs {ref:.4f})")
    check(got < FLOOR, f"lm loss below floor {FLOOR} ({got:.4f})")


def check_head(count, outdir):
    rc, out = run(["/app/infer.py", "head", "--count", str(count), "--output", outdir])
    if rc != 0:
        check(False, f"head run failed count={count}: {out[-300:]}")
        return
    cfgp = os.path.join(outdir, "config.json")
    if not os.path.isfile(cfgp):
        check(False, f"head did not save config {cfgp}")
        return
    c = json.load(open(cfgp))
    carried = c.get("num_labels")
    if carried is None:
        carried = len(c.get("id2label", {}))
    check(carried == count, f"head config carries count {carried}=={count}")
    try:
        from transformers import AutoModelForSequenceClassification
        clf = AutoModelForSequenceClassification.from_pretrained(
            outdir, local_files_only=True)
        check(clf.num_labels == count, f"head reload num_labels {clf.num_labels}=={count}")
        ids = _TOK("kept thaw rook endgame", return_tensors="pt").input_ids
        shape = tuple(clf(ids).logits.shape)
        check(shape == (1, count), f"head forward shape {shape}")
    except Exception as e:
        check(False, f"head reload/forward failed: {e}")


def check_milp(bagfile, outfile):
    rc, out = run(["/app/infer.py", "milp", "--input", bagfile, "--output", outfile])
    if rc != 0:
        check(False, f"milp run failed: {out[-300:]}")
        return
    res = json.load(open(outfile))
    n = int(res["instance_count"])  # documented milp output key (instruction.md)
    lg = res["logits"]; at = res["attention"]
    check(len(lg) == MIC, f"milp logits len {len(lg)}=={MIC}")
    check((n == 0 and len(at) == 0) or len(at) == n,
          f"milp attention len {len(at)} consistent with instances {n}")
    if n > 0:
        check(abs(sum(at) - 1.0) <= 1e-4, f"milp attention unit-sum ({sum(at):.4f})")


def check_wdl(statefile, outfile):
    rc, out = run(["/app/infer.py", "wdl", "--input", statefile, "--output", outfile])
    if rc != 0:
        check(False, f"wdl run failed: {out[-300:]}")
        return
    res = json.load(open(outfile))
    k = int(res["legal_count"])
    ll = res["legal_logits"]; op = res["outcome_probs"]
    check(len(ll) == k, f"wdl legal_logits len {len(ll)}=={k}")
    check(len(op) == WO, f"wdl outcomes len {len(op)}=={WO}")
    check(abs(sum(op) - 1.0) <= 1e-4, f"wdl outcome probs sum 1 ({sum(op):.4f})")


def check_batch(reqfile, outfile):
    if not os.path.isfile(outfile):
        check(False, f"missing batch plan {outfile}")
        return
    src = json.load(open(reqfile))
    budget = src["budget"]
    want_ids = [r["id"] for r in src["requests"]]
    gran = int(budget["granularity"]); bt = int(budget["batch_tok"])
    win = int(budget["window"]); maxw = int(budget["windows"])
    plan = json.load(open(outfile))
    wins = plan.get("windows", [])
    if not wins:
        check(False, "plan has zero windows")
        return
    seen = []
    for w in wins:
        tot = 0
        mbs = w.get("microbatches", [])
        if not mbs:
            check(False, f"window {w.get('window_id')} has no microbatches")
            continue
        for b in mbs:
            tk = int(b["tokens"]); rr = b.get("requests", [])
            if not rr:
                check(False, f"batch {b.get('batch_id')} empty")
            check(tk > 0 and tk % gran == 0, f"batch {b.get('batch_id')} tokens {tk} multiple of {gran}")
            check(tk <= bt, f"batch {b.get('batch_id')} tokens {tk}<=cap {bt}")
            tot += tk
            seen.extend(rr)
        check(w.get("tokens") == tot, f"window {w.get('window_id')} token sum consistent")
        check(tot <= win, f"window {w.get('window_id')} tokens {tot}<=cap {win}")
    check(len(wins) <= maxw, f"window count {len(wins)}<=cap {maxw}")
    check(len(seen) == len(set(seen)), "no duplicated request ids")
    check(sorted(seen) == sorted(want_ids),
          "all request ids covered exactly once (%d)" % len(want_ids))


def run_scenario(name, probe, req, bag, state, headcount, outdir):
    os.makedirs(outdir, exist_ok=True)
    print(f"=== {name} ===")
    lossfile = os.path.join(outdir, "loss.txt")
    rc, out = run(["/app/infer.py", "lm", "--input", probe, "--output", lossfile])
    if rc != 0:
        check(False, f"{name}: lm run failed: {out[-200:]}")
    check_lm(probe, lossfile)
    check_head(headcount, os.path.join(outdir, "head"))
    check_milp(bag, os.path.join(outdir, "milp.json"))
    check_wdl(state, os.path.join(outdir, "wdl.json"))
    planfile = os.path.join(outdir, "plan.json")
    rc2, out2 = run(["/app/infer.py", "batch", "--input", req, "--output", planfile])
    if rc2 != 0:
        check(False, f"{name}: batch run failed: {out2[-200:]}")
    check_batch(req, planfile)


def main():
    print("== engine integrity ==")
    check_engine_integrity()
    print("== default (deliverables) ==")
    check_lm("/app/input/probe.txt", "/app/loss.txt")
    check_batch("/app/input/requests.json", "/app/batch_plan.json")
    check_milp("/app/input/bag.npz", "/tmp/jobs/milp.json")
    check_wdl("/app/input/state.npz", "/tmp/jobs/wdl.json")
    check_head(CFG["default_head_count"], "/tmp/jobs/head")
    for d in sorted(sys.argv[1:]):
        nm = os.path.basename(os.path.normpath(d))
        run_scenario(nm, os.path.join(d, "probe.txt"),
                     os.path.join(d, "requests.json"),
                     os.path.join(d, "bag.npz"),
                     os.path.join(d, "state.npz"),
                     json.load(open(os.path.join(d, "headcount.json")))["count"],
                     f"/tmp/jobs/{nm}")
    rew = 0 if FAILS else 1
    with open(REWARD, "w") as fh:
        fh.write(str(rew))
    print("RESULT reward=%d curses=%d" % (rew, len(FAILS)))


if __name__ == "__main__":
    main()