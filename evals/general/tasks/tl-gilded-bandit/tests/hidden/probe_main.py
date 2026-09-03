#!/usr/bin/env python3
"""Independent verifier for tl-gilded-bandit.

Re-implements (from the documented contract, without importing the shipped
harness) the deterministic bandit simulation: the pre-sampled reward matrix
(seed*2+1, t outer / arm inner), the delay schedule (fixed or uniform from
seed*2+2), oracle totals, and the static baseline.  It then executes the
agent's /app/policy.py on the visible fixture and on every hidden parameter
set in /tests/hidden/cases, applies the per-case budget
    budget = max(0.50 * static_baseline_regret, 0.10 * T)
to the agent's regret, and cross-checks /app/eval_report.json against a
re-run of the policy on the visible fixture (exact reward/regret fields,
plus the change-point estimate must equal the policy's own hook and be
within 250 steps of the true drift_step).  Exit code 0 iff every check
passes.  Must never hang and must never trust the agent's files for ground
truth.
"""
import glob
import importlib.util
import json
import os
import random
import sys

POLICY_PATH = "/app/policy.py"
REPORT_PATH = "/app/eval_report.json"
CASES_DIR = "/tests/hidden/cases"
VISIBLE_PARAMS = "/app/params.json"
EST_TOLERANCE = 250

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL: %s" % msg, file=sys.stderr)


# ---------------------------------------------------------------------------
# Independent simulation (same documented math, fresh implementation).
# ---------------------------------------------------------------------------
def make_matrix(p):
    T, K = p["T"], p["K"]
    ds = p["drift_step"]
    pre, post = p["pre_probs"], p["post_probs"]
    rng = random.Random(p["seed"] * 2 + 1)
    rewards = []
    for t in range(T):
        probs = post if t >= ds else pre
        rewards.append([1 if rng.random() < probs[a] else 0
                        for a in range(K)])
    return rewards


def make_lags(p):
    T = p["T"]
    dt = p["delay"]
    if dt["type"] == "fixed":
        return [dt["d"]] * T
    rng = random.Random(p["seed"] * 2 + 2)
    return [rng.randint(dt["lo"], dt["hi"]) for _ in range(T)]


def drift_probs(p, t):
    return p["post_probs"] if t >= p["drift_step"] else p["pre_probs"]


def best_arm(p, t):
    probs = drift_probs(p, t)
    return max(range(p["K"]), key=lambda a: probs[a])


def static_arm(p):
    probs = p["pre_probs"]
    return max(range(p["K"]), key=lambda a: probs[a])


class Sim:
    """One deterministic episode, mirroring the documented harness run."""

    def __init__(self, p):
        self.p = p
        self.rewards = make_matrix(p)
        self.lags = make_lags(p)

    def run(self, policy):
        p = self.p
        T, K = p["T"], p["K"]
        reveals = {}
        for u in range(T):
            at = u + self.lags[u]
            if at < T:
                reveals.setdefault(at, []).append(u)
        history = []
        arms = []
        total = 0
        for t in range(T):
            for u in reveals.get(t, []):
                history.append({"pull_time": u, "arm": arms[u],
                                "reward": self.rewards[u][arms[u]]})
            a = policy.choose(t, tuple(history))
            if not isinstance(a, int) or isinstance(a, bool) or not (0 <= a < K):
                raise ValueError("bad arm %r at t=%d (K=%d)" % (a, t, K))
            arms.append(a)
            total += self.rewards[t][a]
        oracle = sum(self.rewards[t][best_arm(p, t)] for t in range(T))
        static = sum(self.rewards[t][static_arm(p)] for t in range(T))
        est = None
        if hasattr(policy, "change_point_estimate"):
            try:
                v = policy.change_point_estimate()
                if isinstance(v, int) and not isinstance(v, bool):
                    est = v
            except Exception:
                est = None
        return {
            "cumulative_reward": total,
            "oracle_cumulative_reward": oracle,
            "regret": oracle - total,
            "static_baseline_regret": oracle - static,
            "change_point_estimate": est,
            "T": T,
        }


def load_policy(path):
    spec = importlib.util.spec_from_file_location("agent_policy", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if hasattr(mod, "Policy"):
        return mod.Policy, "class"
    if hasattr(mod, "choose"):
        return mod, "function"
    raise ValueError("policy module missing Policy/choose")


def make_policy(config, loader):
    kind = loader[1]
    if kind == "class":
        try:
            pol = loader[0](dict(config))
        except TypeError:
            pol = loader[0]()
    else:
        pol = loader[0]
    if hasattr(pol, "reset"):
        try:
            pol.reset()
        except Exception:
            pass
    return pol


def run_case(p, loader):
    sim = Sim(p)
    pol = make_policy({"K": p["K"], "T": p["T"]}, loader)
    return sim.run(pol)


def budget_of(p, res):
    return max(0.50 * res["static_baseline_regret"], 0.10 * p["T"])


# ---------------------------------------------------------------------------
# Checks.
# ---------------------------------------------------------------------------
def check_deliverables():
    if not os.path.isfile(POLICY_PATH):
        fail("missing /app/policy.py")
        return False
    if not os.path.isfile(REPORT_PATH):
        fail("missing /app/eval_report.json")
        return False
    return True


def check_visible(loader):
    p = json.load(open(VISIBLE_PARAMS))
    try:
        res = run_case(p, loader)
    except Exception as exc:
        fail("visible case crashed the policy: %s" % exc)
        return
    budget = budget_of(p, res)
    if res["regret"] > budget:
        fail("visible budget exceeded: regret=%d > budget=%.1f"
             % (res["regret"], budget))
    # report recomputation
    try:
        rep = json.load(open(REPORT_PATH))
    except Exception as exc:
        fail("eval_report.json unreadable: %s" % exc)
        return
    if not isinstance(rep, dict):
        fail("eval_report.json must be a JSON object")
        return
    ok_int = True
    for field in ("cumulative_reward", "oracle_cumulative_reward", "regret",
                  "change_point_estimate"):
        v = rep.get(field)
        if not isinstance(v, int) or isinstance(v, bool):
            fail("eval_report.json field %r must be an int" % field)
            ok_int = False
    if not ok_int:
        return
    if rep["cumulative_reward"] != res["cumulative_reward"]:
        fail("report cumulative_reward %d != recomputed %d"
             % (rep["cumulative_reward"], res["cumulative_reward"]))
    if rep["oracle_cumulative_reward"] != res["oracle_cumulative_reward"]:
        fail("report oracle_cumulative_reward %d != recomputed %d"
             % (rep["oracle_cumulative_reward"], res["oracle_cumulative_reward"]))
    if rep["regret"] != res["regret"]:
        fail("report regret %d != recomputed %d" % (rep["regret"], res["regret"]))
    est = rep["change_point_estimate"]
    if est != res["change_point_estimate"]:
        fail("report change_point_estimate %d != policy hook %s"
             % (est, res["change_point_estimate"]))
    if not (0 <= est < p["T"]):
        fail("change_point_estimate %d out of range [0, %d)" % (est, p["T"]))
    if abs(est - p["drift_step"]) > EST_TOLERANCE:
        fail("change_point_estimate %d too far from drift_step %d"
             % (est, p["drift_step"]))
    if res["oracle_cumulative_reward"] <= 0:
        fail("degenerate visible oracle")


def check_hidden(loader):
    if not os.path.isdir(CASES_DIR):
        fail("no hidden cases directory")
        return
    paths = sorted(glob.glob(os.path.join(CASES_DIR, "*.json")))
    if not paths:
        fail("no hidden case files")
        return
    for path in paths:
        p = json.load(open(path))
        try:
            res = run_case(p, loader)
        except Exception as exc:
            fail("hidden case %s crashed the policy: %s"
                 % (os.path.basename(path), exc))
            continue
        budget = budget_of(p, res)
        if res["regret"] > budget:
            fail("hidden case %s budget exceeded: regret=%d > budget=%.1f "
                 "(static_baseline_regret=%d, T=%d)"
                 % (os.path.basename(path), res["regret"], budget,
                    res["static_baseline_regret"], p["T"]))


def main():
    if not check_deliverables():
        return 1
    try:
        loader = load_policy(POLICY_PATH)
    except Exception as exc:
        fail("cannot load /app/policy.py: %s" % exc)
        return 1
    check_visible(loader)
    check_hidden(loader)
    if failures:
        print("verifier failures: %d" % len(failures), file=sys.stderr)
        return 1
    print("all checks passed", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())