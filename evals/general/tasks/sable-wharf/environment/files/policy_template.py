"""Gilded Bandit policy skeleton.

Contract (see /app/env/bandit_env.py and the instructions for the full spec):

  * Policy(config) is instantiated once per simulation with
    config == {"K": int, "T": int}.
  * choose(t, history) -> arm must return an int in [0, K).
      - t is the current step (0-indexed).
      - history is a tuple of dicts
        {"pull_time": int, "arm": int, "reward": 0|1} for every pull whose
        reward has been revealed so far (each pull's reward arrives
        delay(pull_time) steps late, possibly out of order).
  * change_point_estimate() -> int is called exactly once after the run ends;
    return your best estimate of the abrupt-drift step.

The policy is fully online: /app/params.json describes only the shipped
visible fixture and does NOT describe the other parameter sets the policy is
graded on.  Everything about the bandit (arm chances, the drift, the delay)
must be learned from t and history.  The policy must be deterministic and
use only the Python standard library.

This skeleton runs (it just pulls each arm in turn) but is not adaptive and
returns no change-point estimate --- both of which you must implement.
"""
import math

# FIXME: implement a drift-aware learner, e.g. UCB1 with a restart when the
# best arm's recent reward rate collapses, or a sliding-window UCB.  Track
# enough state to return a real change-point estimate from
# change_point_estimate().


class Policy:
    def __init__(self, config):
        self.K = config["K"]
        self.T = config["T"]
        self.pulls = [0] * self.K
        self.reward_seen = [0] * self.K
        self.reward_sum = [0] * self.K
        self.last_len = 0
        self.estimate = None

    def choose(self, t, history):
        # Ingest newly revealed rewards.
        for i in range(self.last_len, len(history)):
            e = history[i]
            a = e["arm"]
            self.reward_seen[a] += 1
            self.reward_sum[a] += e["reward"]
        self.last_len = len(history)

        # UCB1-style index over all arms; n+1 smoothing keeps unseen arms
        # attractive while their first rewards are still in flight.
        lnN = math.log(t + 2.0) if t > 0 else 0.0
        best = None
        best_key = None
        for a in range(self.K):
            n = self.reward_seen[a]
            if n:
                mu = self.reward_sum[a] / n
            else:
                mu = 0.5
            idx = mu + math.sqrt(2.0 * lnN / (n + 1.0))
            key = (idx, -self.pulls[a], -a)
            if best_key is None or key > best_key:
                best_key = key
                best = a
        self.pulls[best] += 1
        return best

    def change_point_estimate(self):
        # FIXME: return your detection of the abrupt drift step.
        return self.estimate if self.estimate is not None else 0