#!/usr/bin/env python3
"""Deterministic seeded replay evaluation of a trained rover policy.

Implements the documented protocol exactly:
  rng = numpy.random.default_rng(seed)
  obs     = rng.standard_normal((n_trials, obs_dim)).astype(numpy.float32)
  correct = rng.integers(0, act_dim, size=n_trials)      # drawn AFTER obs
  action  = argmax over fc2(relu(fc1(obs)))
  reward  = 1.0 if action == correct else reward_neg
"""
import json
import os
import sys

import numpy as np
import torch
import torch.nn as nn


class Policy(nn.Module):
    def __init__(self, obs_dim: int, hidden_dim: int, act_dim: int):
        super().__init__()
        self.fc1 = nn.Linear(obs_dim, hidden_dim)
        self.fc2 = nn.Linear(hidden_dim, act_dim)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.fc2(torch.relu(self.fc1(x)))


def run_case(case_dir: str) -> dict:
    with open(os.path.join(case_dir, "env_config.json"), "r", encoding="utf-8") as fh:
        cfg = json.load(fh)

    obs_dim = int(cfg["obs_dim"])
    hidden_dim = int(cfg["hidden_dim"])
    act_dim = int(cfg["act_dim"])
    seed = int(cfg["seed"])
    n_trials = int(cfg["n_trials"])
    reward_neg = float(cfg["reward_neg"])

    chk = torch.load(os.path.join(case_dir, "policy.pt"), map_location="cpu")
    state_dict = chk["state_dict"]

    model = Policy(obs_dim, hidden_dim, act_dim)
    model.load_state_dict(state_dict, strict=True)
    model.eval()

    rng = np.random.default_rng(seed)
    obs = rng.standard_normal((n_trials, obs_dim)).astype(np.float32)
    correct = rng.integers(0, act_dim, size=n_trials)

    with torch.no_grad():
        logits = model(torch.from_numpy(obs))
        actions = logits.argmax(dim=1).numpy()

    matches = actions == correct
    rewards = np.where(matches, 1.0, reward_neg)

    return {
        "case_id": cfg["case_id"],
        "seed": seed,
        "n_trials": n_trials,
        "n_correct": int(matches.sum()),
        "mean_reward": float(rewards.mean()),
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: evaluate.py <case_dir> <output_json>", file=sys.stderr)
        return 2
    case_dir, out_path = sys.argv[1], sys.argv[2]
    report = run_case(case_dir)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
