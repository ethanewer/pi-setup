#!/bin/bash
#
# Gilded Bandit oracle.  Does the real work from a pristine container:
# authors the adaptive bandit policy as /app/policy.py and produces the
# visible-fixture eval report /app/eval_report.json via the shipped harness.
# Deterministic; never reads /tests.
set -euo pipefail

cat > /app/policy.py <<'PYEOF'
"""Gilded Bandit policy: UCB1 with a collapse-detection restart.

Idea: while the bandit is stationary, plain UCB1 over the full reward
history is cheap (little exploration, tight around the best arm).  The
abrupt drift announces itself by the way: the arm the policy currently
trusts most starts paying out almost nothing.  We monitor the current
full-history leader's stream of revealed rewards; when the recent rate
collapses well below its long-run mean, we restart all statistics (the old
evidence is worthless) and re-learn from scratch.  Delayed, out-of-order
feedback is handled by keying every observation to its pull_time and only
ever counting revealed rewards.

Deterministic: pure arithmetic, no randomness, no wall clock.
"""
import math


class Policy:
    def __init__(self, config):
        self.K = config["K"]
        self.T = config["T"]
        # Full-history UCB1 statistics (revealed rewards only).
        self.counts = [0] * self.K
        self.sums = [0] * self.K
        self.pulls = [0] * self.K
        # Per-arm reward streams in reveal order, for change detection.
        self.stream = [[] for _ in range(self.K)]
        self._seen_len = 0
        self._total_pulls = 0
        self.estimate = None          # detected drift step
        self._suppress_until = -1
        self._rearm_until = -1

    # -- observation ingestion ------------------------------------------------
    def _ingest(self, history):
        for i in range(self._seen_len, len(history)):
            e = history[i]
            a = e["arm"]
            self.stream[a].append(e["reward"])
            self.counts[a] += 1
            self.sums[a] += e["reward"]
        self._seen_len = len(history)

    # -- drift detection --------------------------------------------------------
    def _check_collapse(self, t, history):
        mu = [self.sums[a] / self.counts[a] if self.counts[a] else 0.5
              for a in range(self.K)]
        leader = max(range(self.K), key=lambda a: (mu[a], -self.pulls[a]))
        if self.counts[leader] < 96:
            return
        recent = self.stream[leader][-24:]
        rate = sum(recent) / len(recent)
        # Fire only on a real collapse: recent rate far below the mean and
        # below any plausible stationary rate.
        if rate <= 0.45 and rate <= mu[leader] - 0.40:
            self.estimate = t
            self.counts = [0] * self.K
            self.sums = [0] * self.K
            self.stream = [[] for _ in range(self.K)]
            self._seen_len = len(history)
            self._suppress_until = t + 6 * self.K
            self._rearm_until = t + 24
            return True
        return False

    # -- UCB selection -----------------------------------------------------------
    def choose(self, t, history):
        self._ingest(history)
        if (t >= self._suppress_until and t >= self._rearm_until
                and self._total_pulls >= 60):
            self._check_collapse(t, history)
        lnN = math.log(t + 2.0) if t > 0 else 0.0
        best = None
        best_key = None
        for a in range(self.K):
            n = self.counts[a]
            mu = self.sums[a] / n if n else 0.5
            idx = mu + math.sqrt(2.0 * lnN / (n + 1.0))
            key = (idx, -self.pulls[a], -a)
            if best_key is None or key > best_key:
                best_key = key
                best = a
        self.pulls[best] += 1
        self._total_pulls += 1
        return best

    def change_point_estimate(self):
        return self.estimate if self.estimate is not None else 0
PYEOF

# Visible-fixture eval report, straight off a harness run of the policy.
python3 /app/env/bandit_env.py report \
  --params /app/params.json \
  --policy /app/policy.py \
  --out /app/eval_report.json

# Self-check: the policy/algorithm stays inside the per-case budget on the
# visible fixture (the verifier applies the same bar to hidden sets too).
python3 /app/env/bandit_env.py run \
  --params /app/params.json --policy /app/policy.py \
  | sed 's/^/oracle run: /'
echo "tl-gilded-bandit oracle complete: /app/policy.py + /app/eval_report.json"