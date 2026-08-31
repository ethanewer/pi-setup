#!/bin/bash
# Oracle for kite-mesa: write the rl_lab.py training harness, then RUN it (no
# arguments) so the deliverable /app/policy.json is produced by doing the work.
set -euo pipefail

LAB="/app/rl_lab.py"
OUT="/app/policy.json"

cat > "$LAB" <<'PY'
#!/usr/bin/env python3
"""Cold-storage warehouse robot: grid environment + policy trainer (kite-mesa)."""
import argparse
import json
import math
import random

GOAL_REWARD = 10
STEP_PENALTY = -1
WALL_PENALTY = -5
DELTAS = [(-1, 0), (1, 0), (0, -1), (0, 1)]
EVAL_SEED = 20240517


class GridEnv:
    def __init__(self, size, walls, goal, radius, horizon):
        self.size = int(size)
        self.walls = set((int(r), int(c)) for r, c in walls)
        self.goal = (int(goal[0]), int(goal[1]))
        self.radius = float(radius)
        self.horizon = int(horizon)
        self._free = [(r, c) for r in range(self.size)
                      for c in range(self.size) if (r, c) not in self.walls]
        self.pos = None
        self.steps = 0

    def reset(self, pos=None):
        if pos is None:
            self.pos = random.choice(self._free)
        else:
            self.pos = (int(pos[0]), int(pos[1]))
        self.steps = 0
        return self.pos

    def step(self, action):
        r, c = self.pos
        dr, dc = DELTAS[int(action)]
        tr, tc = r + dr, c + dc
        if not (0 <= tr < self.size and 0 <= tc < self.size):
            reward = STEP_PENALTY          # boundary bounce: stay in place
        elif (tr, tc) in self.walls:
            reward = WALL_PENALTY          # rack bump: stay in place
        else:
            self.pos = (tr, tc)
            d = math.hypot(tr - self.goal[0], tc - self.goal[1])
            reward = GOAL_REWARD if d <= self.radius else STEP_PENALTY
        self.steps += 1
        done = self.steps >= self.horizon
        return int(reward), self.pos, done


def train_policy(env):
    """Finite-horizon value iteration -> greedy policy(pos) -> action."""
    cells = env._free
    V = {p: 0.0 for p in cells}
    PI = {p: 0 for p in cells}
    for _ in range(env.horizon):
        NV = {}
        for (r, c) in cells:
            best, bact = -1e18, 0
            for a, (dr, dc) in enumerate(DELTAS):
                tr, tc = r + dr, c + dc
                if not (0 <= tr < env.size and 0 <= tc < env.size):
                    rew, nxt = STEP_PENALTY, (r, c)
                elif (tr, tc) in env.walls:
                    rew, nxt = WALL_PENALTY, (r, c)
                else:
                    d = math.hypot(tr - env.goal[0], tc - env.goal[1])
                    rew = GOAL_REWARD if d <= env.radius else STEP_PENALTY
                    nxt = (tr, tc)
                val = rew + V[nxt]
                if val > best:
                    best, bact = val, a
            NV[(r, c)] = (best, bact)
        for p in cells:
            V[p] = NV[p][0]
            PI[p] = NV[p][1]

    def policy(pos):
        return PI[(int(pos[0]), int(pos[1]))]

    policy.table = PI
    return policy


def evaluate_policy(env, policy, trials, horizon):
    cells = sorted(env._free)
    rng = random.Random(EVAL_SEED)
    total = 0
    for _ in range(int(trials)):
        env.reset(pos=cells[rng.randrange(len(cells))])
        done = False
        while not done:
            rew, _pos, done = env.step(policy(env.pos))
            total += rew
    return total / float(trials)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="/app/configs/main.json")
    ap.add_argument("--out", default="/app/policy.json")
    args = ap.parse_args(argv)

    with open(args.config, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)
    env = GridEnv(cfg["size"], cfg["walls"], cfg["goal"], cfg["radius"],
                  cfg["horizon"])
    policy = train_policy(env)
    mean = evaluate_policy(env, policy, cfg["trials"], cfg["horizon"])
    artifact = {
        "config": args.config,
        "mean_return": mean,
        "policy": {"%d,%d" % p: int(a) for p, a in sorted(policy.table.items())},
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(artifact, fh, indent=2)
    print("trained policy for %s: mean_return=%.2f -> %s"
          % (args.config, mean, args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
chmod +x "$LAB"

python3 "$LAB" --config /app/configs/main.json --out "$OUT" >/tmp/rl_oracle.log 2>&1

[ -s "$OUT" ]
python3 - <<'EOF'
import json
d = json.load(open("/app/policy.json"))
assert isinstance(d.get("policy"), dict) and d["policy"], "empty policy table"
print("oracle policy OK: %d cells, mean_return=%.2f" % (len(d["policy"]), d["mean_return"]))
EOF
echo "solve.sh: kite-mesa deliverables produced"
