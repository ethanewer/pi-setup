#!/bin/bash
# Verifier for kite-mesa: checks both deliverables, re-EXECUTES the deliverable
# CLI on hidden warehouse layouts, imports the module, validates environment
# semantics against a reference implementation, and requires the trained
# policy to reach each layout's mean-return threshold. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import importlib.util, json, math, os, random, subprocess, sys

LAB = "/app/rl_lab.py"
EVAL_SEED = 20240517
DELTAS = [(-1, 0), (1, 0), (0, -1), (0, 1)]
GOAL_REWARD, STEP_PENALTY, WALL_PENALTY = 10, -1, -5

failures = []


def reference_step(size, walls, goal, radius, pos, action):
    """Independent reference implementation of the documented semantics."""
    r, c = pos
    dr, dc = DELTAS[int(action)]
    tr, tc = r + dr, c + dc
    if not (0 <= tr < size and 0 <= tc < size):
        return STEP_PENALTY, (r, c)
    if (tr, tc) in walls:
        return WALL_PENALTY, (r, c)
    d = math.hypot(tr - goal[0], tc - goal[1])
    return (GOAL_REWARD if d <= radius else STEP_PENALTY), (tr, tc)


def check_edges(env, cfg, tag):
    for name, e in (cfg.get("edge_spec") or {}).items():
        pos = (int(e["pos"][0]), int(e["pos"][1]))
        env.reset(pos=pos)
        rew, npos, done = env.step(int(e["action"]))
        walls = set(map(tuple, map(tuple, cfg["walls"])))
        exp_rew, exp_pos = reference_step(cfg["size"], walls, cfg["goal"],
                                          cfg["radius"], pos, int(e["action"]))
        if int(rew) != exp_rew or tuple(npos) != exp_pos:
            failures.append("%s: edge '%s' got (%r,%r) expected (%r,%r)"
                            % (tag, name, rew, tuple(npos), exp_rew, exp_pos))
        if done:
            failures.append("%s: edge '%s' finished the episode early" % (tag, name))


def seeded_mean(env, policy, trials, horizon):
    cells = sorted(env._free)
    rng = random.Random(EVAL_SEED)
    total = 0
    for _ in range(int(trials)):
        env.reset(pos=cells[rng.randrange(len(cells))])
        done = False
        while not done:
            rew, _p, done = env.step(policy(env.pos))
            total += rew
    return total / float(trials)


def check_layout(cfg_path, tag, tmp_out):
    if not os.path.isfile(cfg_path):
        failures.append("%s: config %s missing" % (tag, cfg_path))
        return
    try:
        with open(cfg_path) as fh:
            cfg = json.load(fh)
    except Exception as e:
        failures.append("%s: config unreadable (%s)" % (tag, e))
        return
    walls = [tuple(w) for w in cfg["walls"]]

    # 1. execute the CLI deliverable on this layout
    if os.path.exists(tmp_out):
        os.remove(tmp_out)
    r = subprocess.run([sys.executable, LAB, "--config", cfg_path,
                        "--out", tmp_out], capture_output=True, text=True,
                       timeout=200)
    if r.returncode != 0 or not os.path.isfile(tmp_out):
        failures.append("%s: CLI failed rc=%d stderr=%s"
                        % (tag, r.returncode, r.stderr[-300:]))
        return
    try:
        art = json.load(open(tmp_out))
        pol_table = art["policy"]
        assert isinstance(pol_table, dict) and pol_table
    except Exception as e:
        failures.append("%s: policy artifact unreadable (%s)" % (tag, e))
        return
    free = [(r0, c0) for r0 in range(cfg["size"]) for c0 in range(cfg["size"])
            if (r0, c0) not in set(walls)]
    if set(pol_table.keys()) != {"%d,%d" % p for p in free}:
        failures.append("%s: policy table does not cover exactly the free cells" % tag)

    # 2. import the module and train on this layout
    try:
        spec = importlib.util.spec_from_file_location("rl_lab_under_test", LAB)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception as e:
        failures.append("%s: cannot import rl_lab.py (%s)" % (tag, e))
        return
    for attr in ("GridEnv", "train_policy", "evaluate_policy"):
        if not hasattr(mod, attr):
            failures.append("%s: module missing %s" % (tag, attr))
            return
    env = mod.GridEnv(cfg["size"], walls, cfg["goal"], cfg["radius"], cfg["horizon"])
    policy = mod.train_policy(env)
    if not callable(policy):
        failures.append("%s: train_policy did not return a callable" % tag)
        return

    # 3. environment semantics edge cases vs reference
    check_edges(env, cfg, tag)

    # 4. verifier's own seeded episode simulation must reach the threshold
    mean = seeded_mean(env, policy, cfg["trials"], cfg["horizon"])
    if mean < cfg["threshold"]:
        failures.append("%s: mean return %.2f below threshold %s"
                        % (tag, mean, cfg["threshold"]))

    # 5. the documented evaluate_policy interface must work
    try:
        val = mod.evaluate_policy(env, policy, cfg["trials"], cfg["horizon"])
        v = float(val)
        if not (math.isfinite(v) and v >= cfg["threshold"]):
            failures.append("%s: evaluate_policy returned %.2f (threshold %s)"
                            % (tag, v, cfg["threshold"]))
    except Exception as e:
        failures.append("%s: evaluate_policy raised (%s)" % (tag, e))


if not os.path.isfile(LAB):
    failures.append("missing /app/rl_lab.py")
else:
    # visible deliverable: /app/policy.json must exist and be a valid artifact
    if not os.path.isfile("/app/policy.json"):
        failures.append("missing /app/policy.json")
    else:
        try:
            art = json.load(open("/app/policy.json"))
            assert isinstance(art.get("policy"), dict) and art["policy"]
        except Exception as e:
            failures.append("/app/policy.json unreadable or empty (%s)" % e)
    check_layout("/app/configs/main.json", "visible", "/tmp/kite_mesa_vis.json")

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            check_layout(os.path.join(hidden_dir, c, "config.json"),
                         "hidden %s" % c, "/tmp/kite_mesa_%s.json" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
