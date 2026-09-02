#!/bin/bash
# Verifier for harbor-keystone (executes-deliverable): re-runs /app/train.py on
# the shipped config and on hidden configs, then independently scores each
# produced policy: optimal mean discounted return via the verifier's own value
# iteration vs the policy's EXACT mean return via a linear solve. Writes 1/0
# to /logs/verifier/reward.txt; never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json
import os
import subprocess
import sys

import numpy as np

TRAINER = "/app/train.py"
VISIBLE_CFG = "/app/rl_config.json"
VISIBLE_POLICY = "/app/policy.json"
PASS_RATIO = 0.95
failures = []


def fail(msg):
    failures.append(msg)


DELTAS = {0: (0, -1), 1: (0, 1), 2: (-1, 0), 3: (1, 0)}
GOAL_R, STEP_R = 100.0, -1.0


def load_cfg(path):
    with open(path, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)
    if not isinstance(cfg, dict):
        raise ValueError("config not an object")
    for key in ("size", "goal", "obstacles", "slip", "gamma"):
        if key not in cfg:
            raise ValueError("missing key %r" % key)
    size = int(cfg["size"])
    gx, gy = int(cfg["goal"][0]), int(cfg["goal"][1])
    obstacles = {(int(a), int(b)) for a, b in cfg["obstacles"]}
    slip = float(cfg["slip"])
    gamma = float(cfg["gamma"])
    if size <= 1 or not (0 <= gx < size and 0 <= gy < size):
        raise ValueError("bad size/goal")
    if (gx, gy) in obstacles:
        raise ValueError("goal is an obstacle")
    if not (0.0 <= slip < 1.0) or not (0.0 < gamma < 1.0):
        raise ValueError("bad slip/gamma")
    return size, (gx, gy), obstacles, slip, gamma


class Floor:
    def __init__(self, cfg):
        self.size, self.goal, self.obs, self.slip, self.gamma = cfg
        self.free = [(x, y) for x in range(self.size) for y in range(self.size)
                     if (x, y) != self.goal and (x, y) not in self.obs]
        self.idx = {p: i for i, p in enumerate(self.free)}

    def move(self, pos, action):
        dx, dy = DELTAS[action]
        nx, ny = pos[0] + dx, pos[1] + dy
        if 0 <= nx < self.size and 0 <= ny < self.size and (nx, ny) not in self.obs:
            return (nx, ny)
        return pos

    def outcomes(self, pos, action):
        """[(prob, reward, next_or_None)] for intended `action` at pos."""
        out = []
        for executed in range(4):
            q = (1.0 - self.slip) if executed == action else self.slip / 4.0
            if q == 0.0:
                continue
            nxt = self.move(pos, executed)
            if nxt == self.goal:
                out.append((q, GOAL_R, None))
            else:
                out.append((q, STEP_R, nxt))
        return out

    def value_iteration(self, tol=1e-12, max_iter=100000):
        V = np.zeros(len(self.free))
        for _ in range(max_iter):
            nv = np.empty_like(V)
            for p in self.free:
                i = self.idx[p]
                best = -np.inf
                for a in range(4):
                    val = 0.0
                    for q, r, nxt in self.outcomes(p, a):
                        fut = 0.0 if nxt is None else self.gamma * V[self.idx[nxt]]
                        val += q * (r + fut)
                    best = max(best, val)
                nv[i] = best
            if np.max(np.abs(nv - V)) < tol:
                return nv
            V = nv
        return V

    def policy_value(self, actions):
        """Exact value of a fixed policy via linear solve; None if invalid."""
        n = len(self.free)
        A = np.eye(n)
        b = np.zeros(n)
        for p in self.free:
            i = self.idx[p]
            key = "%d,%d" % p
            if key not in actions:
                return None
            a = actions[key]
            if not isinstance(a, int) or not (0 <= a <= 3):
                return None
            for q, r, nxt in self.outcomes(p, a):
                b[i] += q * r
                if nxt is not None:
                    A[i, self.idx[nxt]] -= self.gamma * q
        try:
            return np.linalg.solve(A, b)
        except np.linalg.LinAlgError:
            return None


def run_trainer(cfg_path, out_path):
    try:
        return subprocess.run(
            [sys.executable, TRAINER, "--config", cfg_path, "--out", out_path],
            capture_output=True, text=True, timeout=240,
        )
    except Exception as exc:
        fail("trainer crashed on %s: %r" % (cfg_path, exc))
        return None


def eval_policy(tag, cfg_path, policy_path):
    try:
        cfg = load_cfg(cfg_path)
    except Exception as exc:
        fail("%s: verifier cannot load config %s (%r)" % (tag, cfg_path, exc))
        return
    try:
        with open(policy_path) as fh:
            pol = json.load(fh)
    except Exception as exc:
        fail("%s: policy %s unreadable (%r)" % (tag, policy_path, exc))
        return
    if not isinstance(pol, dict) or not isinstance(pol.get("actions"), dict):
        fail("%s: policy JSON lacks an 'actions' object" % tag)
        return
    floor = Floor(cfg)
    Vstar = floor.value_iteration()
    Vpol = floor.policy_value(pol["actions"])
    if Vpol is None:
        fail("%s: policy invalid (missing free cells or bad actions)" % tag)
        return
    opt_mean = float(Vstar.mean())
    pol_mean = float(Vpol.mean())
    # self-check: the verifier's own greedy policy must be ~optimal
    greedy = {}
    for p in floor.free:
        vals = []
        for a in range(4):
            val = 0.0
            for q, r, nxt in floor.outcomes(p, a):
                fut = 0.0 if nxt is None else floor.gamma * Vstar[floor.idx[nxt]]
                val += q * (r + fut)
            vals.append(val)
        greedy["%d,%d" % p] = int(np.argmax(vals))
    Vgreedy = floor.policy_value(greedy)
    if Vgreedy is None or float(Vgreedy.mean()) < 0.999 * opt_mean:
        fail("%s: verifier self-check failed (env/VI mismatch)" % tag)
        return
    needed = PASS_RATIO * opt_mean
    if pol_mean < needed:
        fail("%s: policy mean %.4f < %.4f (95%% of optimal %.4f)"
             % (tag, pol_mean, needed, opt_mean))
    else:
        print("  %s: policy mean %.4f vs optimal %.4f" % (tag, pol_mean, opt_mean))


# ---- 1. deliverables exist --------------------------------------------------
if not os.path.isfile(TRAINER):
    fail("missing /app/train.py")
if not os.path.isfile(VISIBLE_POLICY):
    fail("missing /app/policy.json")

# ---- 2. visible config: re-run trainer + score the shipped policy -----------
if os.path.isfile(TRAINER) and os.path.isfile(VISIBLE_CFG):
    r = run_trainer(VISIBLE_CFG, "/tmp/vis_policy.json")
    if r is None or r.returncode != 0:
        fail("visible config: trainer exited %s (%s)"
             % (r.returncode if r else "?", (r.stderr[-200:] if r else "")))
    else:
        eval_policy("visible-rerun", VISIBLE_CFG, "/tmp/vis_policy.json")
        if os.path.isfile(VISIBLE_POLICY):
            eval_policy("visible-artifact", VISIBLE_CFG, VISIBLE_POLICY)
        else:
            fail("visible artifact missing after rerun")

# ---- 3. hidden configs ------------------------------------------------------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        fail("no hidden cases present")
    for case in cases:
        cfg_path = os.path.join(hidden_dir, case, "config.json")
        if not os.path.isfile(cfg_path):
            fail("hidden '%s': missing config.json" % case)
            continue
        if case.startswith("bad_"):
            out = "/tmp/h_%s_policy.json" % case
            r = run_trainer(cfg_path, out)
            if r is None or r.returncode == 0:
                fail("hidden '%s': expected non-zero exit for bad config" % case)
            continue
        out = "/tmp/h_%s_policy.json" % case
        if os.path.exists(out):
            os.remove(out)
        r = run_trainer(cfg_path, out)
        if r is None or r.returncode != 0:
            fail("hidden '%s': trainer exited %s"
                 % (case, r.returncode if r else "?"))
        else:
            eval_policy("hidden:%s" % case, cfg_path, out)
else:
    fail("missing /tests/hidden")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
exit 0
