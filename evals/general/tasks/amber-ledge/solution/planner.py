#!/usr/bin/env python3
"""Treadmill-core batch action-plan evaluator.

Reads a JSON batch of action plans and returns, for every plan in the batch,
the cumulative reward obtained by running the plan's actions one at a time
through the magazine step function. The returned sequence is aligned with the
input batch (index i <-> plan i).

CLI:
    python3 planner.py <input.json> <output.json>

input.json -> [
   ["gather","chop","free"],       # a plan is a list of action names
   ["forge","gather"],             # ...more plans...
]
output.json -> [ <cumulative reward per plan>, ... ]   (same length, same order)

Step model (magazine): a running state tracks three raw materials
  f (food), w (wood), o (ore), all starting at 0.
Each action yields an immediate reward increment and may mutate the state:

  "gather" : f += 1;   reward += 5
  "chop"   : w += 2;   reward += 7
  "free"   : f += 1;   reward += 1
  "quarry" : o += 1;   reward += 1 if ore was 0 before, else reward += 6
  "forge"  : requires w >= 2 (consumes 2 w): reward += 14; else reward += 0
  "market" : reward += food (current f); no state change
  "idle"   : reward += 0

Cumulative reward is the running sum of action rewards over the plan.
Empty plan ("[]") yields reward 0. An action string that is not one of the
known actions is skipped (reward += 0). A plan that is not a list yields
reward 0. A batch that is not a list yields an empty output list.

The output is the plain JSON list of per-plan cumulative rewards.
"""

import sys
import json

ACTIONS = frozenset({
    "gather": None, "chop": None, "free": None,
    "quarry": None, "forge": None, "market": None, "idle": None,
})

def step(state, action):
    """Advance `state` (dict of f,w,o) by one action; return its reward."""
    r = 0
    if action == "gather":
        state["f"] += 1
        r = 5
    elif action == "chop":
        state["w"] += 2
        r = 7
    elif action == "free":
        state["f"] += 1
        r = 1
    elif action == "quarry":
        state["o"] += 1
        r = 1 if state["o"] == 1 else 6
    elif action == "forge":
        if state["w"] >= 2:
            state["w"] -= 2
            r = 14
        else:
            r = 0
    elif action == "market":
        r = state["f"]
    elif action == "idle":
        r = 0
    # unknown action -> skipped (reward 0)
    return r


def evaluate_batch(plans):
    """Return list of cumulative rewards aligned with `plans`."""
    out = []
    for plan in plans:
        if not isinstance(plan, list):
            out.append(0)
            continue
        state = {"f": 0, "w": 0, "o": 0}
        total = 0
        for a in plan:
            if not isinstance(a, str):
                continue
            total += step(state, a)
        out.append(total)
    return out


def main():
    inp, outp = sys.argv[1], sys.argv[2]
    with open(inp, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, list):
        raise ValueError("batch must be a JSON list of plans")
    results = evaluate_batch(data)
    with open(outp, "w", encoding="utf-8") as fh:
        json.dump(results, fh)
    sys.stdout.write("ok\n")


if __name__ == "__main__":
    main()