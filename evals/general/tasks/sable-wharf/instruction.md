# Sable Wharf: learn a drifting slot machine with delayed payout reports

A casino has shuffled its golden-mile machines again.  This data science task
exercises the competency of **online learning for a
nonstationary multi-armed bandit with delayed feedback and abrupt drift**:
K slot machines (arms) each pay out 1 coin per pull with an unknown chance;
part way through the session the chances abruptly drift (two machines swap
quality), and every payout is only *reported* D steps after the pull that
earned it — so the evidence about your own past pulls arrives late and out
of order.  Your job is the learning policy that keeps the cumulative take
high before and after the drift, plus a short eval report.

## Environment

A deterministic simulation harness is shipped at:

- `/app/env/bandit_env.py` — the bandit harness (read it; it is the contract).
- `/app/params.json` — the visible fixture's parameters (see `info` below).
- `/app/policy_template.py` — a runnable skeleton; start by copying it to
  `/app/policy.py` and extending it.

There is no network and only the Python standard library is available.
Everything is CPU and deterministic.

### Simulation model (exactly, from the harness)

- K arms, horizon T steps t = 0 .. T-1.  At time t arm a earns
  r ∈ {0,1} with P(r=1) = p_a(t), where
  `p_a(t) = pre_probs[a]` for t < `drift_step` and
  `p_a(t) = post_probs[a]` for t ≥ `drift_step`.
- The entire (T × K) reward matrix is **pre-sampled once** at construction
  with a fixed seed, so it is a pure function of the params; the visible
  fixture is `python3 /app/env/bandit_env.py info --params /app/params.json`
  away.
- A pull at time u is revealed at time u + delay(u).  `delay` is either
  `{"type": "fixed", "d": D}` or `{"type": "uniform", "lo": L, "hi": H}`
  (per-pull integer drawn from a dedicated seeded RNG).  Because delays vary
  per pull, rewards arrive **out of order**: history entries carry their own
  `pull_time`, so attribution is always unambiguous.
- Oracle: best arm at time t is `argmax_a p_a(t)` (ties → lowest a).
  `oracle_cumulative_reward = Σ_t rewards[t][best_arm(t)]`.
- Static baseline: always pull `argmax_a pre_probs[a]` (ties → lowest a);
  `static_baseline_regret` is the oracle minus that policy's total.

## Deliverable 1: `/app/policy.py`

Implement the policy module.  The harness instantiates it once per run and
calls `choose(t, history)` for t = 0 … T-1:

```
class Policy:
    def __init__(self, config):        # config == {"K": int, "T": int}
    def choose(self, t, history) -> int          # 0 <= arm < K
    def change_point_estimate(self) -> int       # called once after the run
```

- `history` is a tuple of dicts `{"pull_time": int, "arm": int, "reward": 0|1}`
  for every pull whose reward has been revealed by step t (pull_time +
  delay(pull_time) ≤ t), in reveal order.  Entries appear once each.
- `config` is the **only** reliable source of K and T.  `/app/params.json`
  describes only this visible fixture; the grader runs your policy on other
  parameter sets where that file's numbers do **not** apply.  Your policy
  must be fully online — learn arm chances, the drift, and the delay purely
  from `t` and `history`.
- Keep everything inside the Policy instance (no shared/global mutable
  state that could leak between runs).
- Be deterministic: fixed arithmetic only, no wall clock, no unseeded
  randomness — the grader reproduces your run exactly.

You must deliver real drift adaptation (a plain fixed-policy or a policy
that cannot re-find the best arm after the switch fails the hidden sets) and
a real change-point estimate.

## Deliverable 2: `/app/eval_report.json`

A JSON object with exactly these integer fields, produced from your policy's
run on the **visible** fixture (easiest: `python3 /app/env/bandit_env.py
report --params /app/params.json --policy /app/policy.py`):

```
{
  "cumulative_reward": <int>,
  "oracle_cumulative_reward": <int>,
  "regret": <int>,
  "change_point_estimate": <int>
}
```

The change-point estimate must be your algorithm's own best guess of the
drift step (in [0, T)); the grader re-runs your policy, asks it for its
estimate via `change_point_estimate()`, and requires the report value to
match — so don't just copy a number out of params.json.

## How it is graded

The verifier re-executes `/app/policy.py` inside its own copy of the
documented simulation (it recomputes the reward matrix, oracle totals and
the static baseline itself) on four parameter sets:

1. the visible fixture (params.json) — for the report checks: the report's
   `cumulative_reward` / `oracle_cumulative_reward` / `regret` must equal the
   verifier's re-run exactly, and `|change_point_estimate - drift_step|`
   must be ≤ 250.
2. three hidden parameter sets (different seeds, arm counts, drift steps,
   and delay schedules — including a no-drift case, a three-way rotation,
   and long delays).

For every set the verifier computes a per-case budget:

```
budget = max(0.50 * static_baseline_regret, 0.10 * T)
```

and requires your regret (oracle minus your cumulative reward, both from
the verifier's own simulation) to satisfy `regret <= budget`.  A policy
that hardcodes the visible fixture (any arm count, drift step, or swap) is
caught by the hidden sets; a policy that never adapts fails the drifting
sets; an over-eager explorer fails the no-drift set.

## Order of work

1. `python3 /app/env/bandit_env.py info --params /app/params.json` — read
   the fixture.
2. Copy `/app/policy_template.py` to `/app/policy.py`; implement the
   learner and the estimate.
3. Iterate with `python3 /app/env/bandit_env.py run --params
   /app/params.json --policy /app/policy.py`.
4. Write the report (see Deliverable 2) and re-check it with `run` — the
   numbers must be stable across runs.