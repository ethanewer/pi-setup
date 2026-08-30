#!/bin/bash
# Verifier for alder-fathom: EXECUTES the deliverable /app/evaluate.py on the
# visible case and on every hidden case, compares against an independent
# reference implementation of the documented replay protocol, checks
# determinism (byte-identical reruns) and the visible deliverable
# /app/eval_report.json. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
export TOKENIZERS_PARALLELISM=false
reward=0

python3 - <<'PY'
import json, os, subprocess, sys, tempfile

import numpy as np
import torch
import torch.nn as nn

SOLVE = "/app/evaluate.py"
failures = []


class RefPolicy(nn.Module):
    def __init__(self, obs_dim, hidden_dim, act_dim):
        super().__init__()
        self.fc1 = nn.Linear(obs_dim, hidden_dim)
        self.fc2 = nn.Linear(hidden_dim, act_dim)

    def forward(self, x):
        return self.fc2(torch.relu(self.fc1(x)))


def reference(case_dir):
    """Independent reimplementation of the documented protocol."""
    with open(os.path.join(case_dir, "env_config.json")) as fh:
        cfg = json.load(fh)
    chk = torch.load(os.path.join(case_dir, "policy.pt"), map_location="cpu")
    sd = chk["state_dict"]
    m = RefPolicy(int(cfg["obs_dim"]), int(cfg["hidden_dim"]), int(cfg["act_dim"]))
    m.load_state_dict(sd, strict=True)
    m.eval()
    rng = np.random.default_rng(int(cfg["seed"]))
    obs = rng.standard_normal((int(cfg["n_trials"]), int(cfg["obs_dim"]))).astype(np.float32)
    correct = rng.integers(0, int(cfg["act_dim"]), size=int(cfg["n_trials"]))
    with torch.no_grad():
        actions = m(torch.from_numpy(obs)).argmax(dim=1).numpy()
    matches = actions == correct
    rewards = np.where(matches, 1.0, float(cfg["reward_neg"]))
    return {
        "case_id": cfg["case_id"],
        "seed": int(cfg["seed"]),
        "n_trials": int(cfg["n_trials"]),
        "n_correct": int(matches.sum()),
        "mean_reward": float(rewards.mean()),
    }


def run_agent(case_dir):
    """Run the deliverable on a case; return parsed JSON dict or None."""
    if not os.path.isfile(SOLVE):
        return None
    out = os.path.join(tempfile.mkdtemp(prefix="alder_fathom_"), "report.json")
    try:
        r = subprocess.run([sys.executable, SOLVE, case_dir, out],
                           capture_output=True, text=True, timeout=240)
    except Exception as e:
        print("[verifier] agent run crashed: %r" % e)
        return None
    if r.returncode != 0 or not os.path.exists(out):
        print("[verifier] agent run failed rc=%s" % r.returncode)
        return None
    try:
        with open(out) as fh:
            got = json.load(fh)
    except Exception as e:
        print("[verifier] agent output unreadable: %r" % e)
        return None
    if not isinstance(got, dict):
        return None
    return got


def compare(got, want, label):
    if not isinstance(got, dict):
        failures.append("%s: output is not a JSON object" % label)
        return
    keys = set(got.keys())
    if keys != {"case_id", "seed", "n_trials", "n_correct", "mean_reward"}:
        failures.append("%s: wrong key set %s" % (label, sorted(keys)))
        return
    for k in ("case_id", "seed", "n_trials", "n_correct"):
        if got[k] != want[k]:
            failures.append("%s: %s = %r != %r" % (label, k, got[k], want[k]))
    try:
        if abs(float(got["mean_reward"]) - want["mean_reward"]) > 1e-9:
            failures.append("%s: mean_reward %r != %r"
                            % (label, got["mean_reward"], want["mean_reward"]))
    except Exception:
        failures.append("%s: mean_reward not a number" % label)


# ---- visible case ----
if not os.path.isdir("/app/case"):
    failures.append("visible fixture /app/case missing")
else:
    want = reference("/app/case")
    got = run_agent("/app/case")
    if got is None:
        failures.append("visible case: deliverable did not run")
    else:
        compare(got, want, "visible")

    # determinism: second run must be byte-identical
    out2 = os.path.join(tempfile.mkdtemp(prefix="alder_fathom_d_"), "report2.json")
    try:
        subprocess.run([sys.executable, SOLVE, "/app/case", out2],
                       capture_output=True, text=True, timeout=240)
        with open(out2, "rb") as fh:
            b2 = fh.read()
        out1 = os.path.join(tempfile.mkdtemp(prefix="alder_fathom_d_"), "report1.json")
        subprocess.run([sys.executable, SOLVE, "/app/case", out1],
                       capture_output=True, text=True, timeout=240)
        with open(out1, "rb") as fh:
            b1 = fh.read()
        if b1 != b2:
            failures.append("determinism: two runs differ")
    except Exception as e:
        failures.append("determinism rerun crashed: %r" % e)

# ---- visible deliverable: /app/eval_report.json ----
if os.path.isfile("/app/eval_report.json"):
    try:
        with open("/app/eval_report.json") as fh:
            got = json.load(fh)
        if os.path.isdir("/app/case"):
            compare(got, reference("/app/case"), "eval_report.json")
    except Exception as e:
        failures.append("eval_report.json unreadable: %r" % e)
else:
    failures.append("missing /app/eval_report.json")

# ---- hidden cases ----
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        if not (os.path.isfile(os.path.join(base, "env_config.json"))
                and os.path.isfile(os.path.join(base, "policy.pt"))):
            failures.append("hidden '%s' malformed" % c)
            continue
        want = reference(base)
        got = run_agent(base)
        if got is None:
            failures.append("hidden '%s': deliverable did not run" % c)
        else:
            compare(got, want, "hidden '%s'" % c)
else:
    failures.append("no /tests/hidden")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
