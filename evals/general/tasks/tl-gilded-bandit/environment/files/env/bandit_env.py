#!/usr/bin/env python3
"""Gilded Bandit: deterministic nonstationary multi-armed bandit harness.

Until the gold run, a gambler plays the same slot machine every time.  The
moment the vein shifts, the machine that paid yesterday starts paying out
dirt --- and everyone who kept playing it went broke.  This harness simulates
exactly that: K arms with unknown reward chances, a single abrupt drift part
way through the horizon, and delayed feedback: each pull's reward is only
revealed D steps later, so the evidence about what happened arrives out of
order.  The learning policy must attribute rewards to their pull times and
recover after the drift.

Simulation model (documented; the verifier re-implements it independently)

  * K arms, horizon T steps t = 0 .. T-1.
  * At pull time t arm a earns reward r in {0, 1} with P(r=1) = p_a(t), where
        p_a(t) = pre_probs[a]   if t <  drift_step
        p_a(t) = post_probs[a]  if t >= drift_step
  * The whole (T x K) reward matrix is PRE-SAMPLED at construction with a
    dedicated seeded RNG, so it is a pure function of the params:
        reward_rng = random.Random(seed * 2 + 1)
        for t in 0..T-1:
            for a in 0..K-1:
                rewards[t][a] = 1 if reward_rng.random() < p_a(t) else 0
    (t outer, arm inner --- this exact order is part of the contract.)
  * Each pull at time u is revealed (appended to the policy history) at time
    u + delay(u).  The delay schedule:
        delay = {"type": "fixed",   "d": D}  -> delay(u) = D for every u
        delay = {"type": "uniform", "lo": L, "hi": H}
            -> delay(u) = rng.randint(L, H) with a separate dedicated RNG
               random.Random(seed * 2 + 2), drawn once per pull in increasing
               u order.
    Delays vary per pull, so rewards may arrive OUT OF ORDER; every history
    entry carries its own pull_time.
  * Oracle: at time t the best arm b(t) = argmax_a p_a(t) (ties -> lowest a).
    oracle_cumulative_reward = sum_t rewards[t][b(t)].
  * Static baseline: always pull s = argmax_a pre_probs[a] (ties -> lowest a).
    static_baseline_regret = oracle_cumulative_reward - (its cumulative).

Policy interface (implement in /app/policy.py)

    class Policy:
        def __init__(self, config):   # config == {"K": int, "T": int}
        def choose(self, t, history) -> int     # 0 <= arm < K
        def change_point_estimate(self) -> int  # called once after the run

  * The harness instantiates Policy(config) exactly once per simulation and
    calls choose(t, history) for t = 0 .. T-1.
  * history is a tuple of dicts
        {"pull_time": <int>, "arm": <int>, "reward": <0|1>}
    for every pull whose reward has been revealed by step t (u + delay(u)
    <= t), in reveal order, per reveal step ascending pull_time.  Entries are
    appended once; the same pull never appears twice.
  * config is the ONLY source of K/T: /app/params.json describes only the
    shipped visible fixture and is NOT valid for other parameter sets the
    policy may be run against.  A policy must be fully online: everything
    else about the bandit must be learned from t and history.
  * The policy must be deterministic (no wall clock, no unseeded randomness):
    graded runs are reproduced exactly and cross-checked against the report.

CLI

    python3 /app/env/bandit_env.py info    --params P          # human summary
    python3 /app/env/bandit_env.py oracle  --params P          # oracle numbers
    python3 /app/env/bandit_env.py run     --params P --policy M.py [--out R.json]
    python3 /app/env/bandit_env.py report  --params P --policy M.py [--out REPORT.json]
        # run + write the eval report (cumulative_reward, oracle_cumulative_reward,
        # regret, change_point_estimate) to --out or /app/eval_report.json by default

The run/report CLI exit 0 on success and print a one-line summary; they exit
non-zero with a diagnostic if the policy misbehaves (invalid arm, exception).
"""
import argparse
import importlib.util
import json
import random
import sys

REQUIRED_KEYS = ("K", "T", "seed", "pre_probs", "post_probs", "drift_step",
                 "delay")


def load_params(path):
    with open(path) as fh:
        p = json.load(fh)
    validate_params(p)
    return p


def validate_params(p):
    for k in REQUIRED_KEYS:
        if k not in p:
            raise ValueError("params missing key %r" % k)
    K = p["K"]
    if not isinstance(K, int) or isinstance(K, bool) or K < 2:
        raise ValueError("K must be an int >= 2")
    for key in ("pre_probs", "post_probs"):
        v = p[key]
        if not (isinstance(v, list) and len(v) == K
                and all(isinstance(x, (int, float)) and 0.0 <= x <= 1.0
                        for x in v)):
            raise ValueError("%s must be a length-K list of probabilities"
                             % key)
    T = p["T"]
    if not isinstance(T, int) or isinstance(T, bool) or T < 100:
        raise ValueError("T must be an int >= 100")
    ds = p["drift_step"]
    if not isinstance(ds, int) or isinstance(ds, bool) or not (0 <= ds <= T):
        raise ValueError("drift_step must satisfy 0 <= drift_step <= T")
    if not isinstance(p["seed"], int) or isinstance(p["seed"], bool):
        raise ValueError("seed must be an int")
    dt = p["delay"]
    if isinstance(dt, dict):
        if dt.get("type") == "fixed":
            d = dt.get("d")
            if not isinstance(d, int) or isinstance(d, bool) or d < 1:
                raise ValueError("fixed delay needs int d >= 1")
        elif dt.get("type") == "uniform":
            lo, hi = dt.get("lo"), dt.get("hi")
            if not (isinstance(lo, int) and isinstance(hi, int)
                    and not isinstance(lo, bool) and not isinstance(hi, bool)
                    and 1 <= lo <= hi):
                raise ValueError("uniform delay needs ints 1 <= lo <= hi")
        else:
            raise ValueError("delay.type must be 'fixed' or 'uniform'")
    else:
        raise ValueError("delay must be a dict")


def sample_reward_matrix(p):
    """Deterministic (T x K) reward matrix.  t outer, arm inner (contract)."""
    T, K = p["T"], p["K"]
    ds = p["drift_step"]
    pre, post = p["pre_probs"], p["post_probs"]
    rng = random.Random(p["seed"] * 2 + 1)
    mat = []
    for t in range(T):
        probs = post if t >= ds else pre
        mat.append([1 if rng.random() < probs[a] else 0 for a in range(K)])
    return mat


def sample_delays(p):
    T = p["T"]
    dt = p["delay"]
    if dt["type"] == "fixed":
        return [dt["d"]] * T
    rng = random.Random(p["seed"] * 2 + 2)
    lo, hi = dt["lo"], dt["hi"]
    return [rng.randint(lo, hi) for _ in range(T)]


class BanditEnv:
    def __init__(self, params):
        self.params = params
        self.K = params["K"]
        self.T = params["T"]
        self.pre_probs = params["pre_probs"]
        self.post_probs = params["post_probs"]
        self.drift_step = params["drift_step"]
        self.rewards = sample_reward_matrix(params)
        self.delays = sample_delays(params)

    def prob_at(self, t, arm):
        return self.post_probs[arm] if t >= self.drift_step else self.pre_probs[arm]

    def best_arm(self, t):
        return max(range(self.K), key=lambda a: self.prob_at(t, a))

    def static_arm(self):
        return max(range(self.K), key=lambda a: self.pre_probs[a])

    def run(self, policy):
        """Run one episode against `policy`; returns the deterministic result."""
        T, K = self.T, self.K
        arrivals = {}
        for u in range(T):
            at = u + self.delays[u]
            if at < T:
                arrivals.setdefault(at, []).append(u)
        history = []
        arms = []
        cumulative = 0
        for t in range(T):
            for u in arrivals.get(t, []):
                history.append({"pull_time": u, "arm": arms[u],
                                "reward": self.rewards[u][arms[u]]})
            arm = policy.choose(t, tuple(history))
            if isinstance(arm, bool) or not isinstance(arm, int):
                raise ValueError("choose() must return an int arm, got %r"
                                 % (arm,))
            if not (0 <= arm < K):
                raise ValueError("invalid arm %r at t=%d (K=%d)" % (arm, t, K))
            arms.append(arm)
            cumulative += self.rewards[t][arm]
        oracle = sum(self.rewards[t][self.best_arm(t)] for t in range(T))
        static = sum(self.rewards[t][self.static_arm()] for t in range(T))
        per_arm = {}
        for a in arms:
            per_arm[str(a)] = per_arm.get(str(a), 0) + 1
        estimate = None
        if hasattr(policy, "change_point_estimate"):
            try:
                est = policy.change_point_estimate()
                if isinstance(est, int) and not isinstance(est, bool):
                    estimate = est
            except Exception:
                estimate = None
        return {
            "K": K, "T": T, "drift_step": self.drift_step,
            "cumulative_reward": cumulative,
            "oracle_cumulative_reward": oracle,
            "regret": oracle - cumulative,
            "static_arm": self.static_arm(),
            "static_baseline_regret": oracle - static,
            "per_arm_pulls": per_arm,
            "change_point_estimate": estimate,
        }


def load_policy(path):
    """Load a policy module.  Returns (maker, kind) where kind is 'class' or
    'function'.  The class contract: Policy(config) exposing choose(t, history)
    and change_point_estimate().  The function contract (also supported):
    module-level choose(t, history) with optional reset()."""
    spec = importlib.util.spec_from_file_location("agent_policy", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if hasattr(module, "Policy"):
        return module.Policy, "class"
    if hasattr(module, "choose"):
        return module, "function"
    raise ValueError("policy module must define a Policy class or a "
                     "module-level choose(t, history) function")


def make_policy(config, loader):
    maker, kind = loader
    if kind == "class":
        try:
            policy = maker(dict(config))
        except TypeError:
            policy = maker()
    else:
        policy = maker
    if hasattr(policy, "reset"):
        try:
            policy.reset()
        except Exception:
            pass
    return policy


def run_once(params, policy_path):
    loader = load_policy(policy_path)
    env = BanditEnv(params)
    policy = make_policy({"K": env.K, "T": env.T}, loader)
    return env.run(policy)


def _summary(result):
    return ("K=%d T=%d drift_step=%d -> cumulative=%d oracle=%d regret=%d "
            "static_baseline_regret=%d change_point=%s" % (
                result["K"], result["T"], result["drift_step"],
                result["cumulative_reward"], result["oracle_cumulative_reward"],
                result["regret"], result["static_baseline_regret"],
                result["change_point_estimate"]))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Gilded Bandit harness")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("info")
    sp.add_argument("--params", required=True)

    sp = sub.add_parser("oracle")
    sp.add_argument("--params", required=True)

    for name in ("run", "report"):
        sp = sub.add_parser(name)
        sp.add_argument("--params", required=True)
        sp.add_argument("--policy", required=True)
        sp.add_argument("--out", default=None)

    args = ap.parse_args(argv)
    params = load_params(args.params)
    if args.cmd == "info":
        env = BanditEnv(params)
        print("K=%d T=%d seed=%d drift_step=%d" % (env.K, env.T,
                                                   params["seed"],
                                                   env.drift_step))
        print("pre_probs=%s" % env.pre_probs)
        print("post_probs=%s" % env.post_probs)
        print("delay=%s" % params["delay"])
        print("best pre-drift arm=%d  best post-drift arm=%d  static_arm=%d"
              % (env.best_arm(0), env.best_arm(env.T - 1), env.static_arm()))
        return 0
    if args.cmd == "oracle":
        env = BanditEnv(params)
        oracle = sum(env.rewards[t][env.best_arm(t)] for t in range(env.T))
        static = sum(env.rewards[t][env.static_arm()] for t in range(env.T))
        print("oracle_cumulative_reward=%d" % oracle)
        print("static_baseline_cumulative_reward=%d" % static)
        print("static_baseline_regret=%d" % (oracle - static))
        return 0
    result = run_once(params, args.policy)
    print(_summary(result))
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(result, fh, indent=2)
    if args.cmd == "report":
        report = {
            "cumulative_reward": result["cumulative_reward"],
            "oracle_cumulative_reward": result["oracle_cumulative_reward"],
            "regret": result["regret"],
            "change_point_estimate": result["change_point_estimate"],
        }
        out = args.out or "/app/eval_report.json"
        with open(out, "w") as fh:
            json.dump(report, fh, indent=2)
        print("wrote eval report to %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())