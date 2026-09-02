#!/usr/bin/env python3
"""Independent verifier for opal-fathom.

  python3 verify.py <casedir> <outdir_json>

Re-implements the documented seeded rollout from the case's env_config.json /
policy.npz (never from the agent's code), then runs the agent's deliverable
program on the case and requires an exact, reproducible match. Exits 0 only
when all checks pass.

The verifier must never crash on malformed or missing agent output: every
parse is guarded and every failure is recorded as a FAIL line.
"""
import json
import os
import subprocess
import sys

import numpy as np

REQUIRED_KEYS = ["case_id", "seed", "episodes", "horizon", "mean_reward",
                 "episode_rewards", "total_steps"]
TOL = 1e-9


def reference_rollout(casedir):
    """Independent implementation of the documented recipe."""
    with open(os.path.join(casedir, "env_config.json")) as fh:
        cfg = json.load(fh)
    policy_name = cfg.get("policy_file", "policy.npz")
    with np.load(os.path.join(casedir, policy_name)) as z:
        W1 = np.asarray(z["W1"], dtype=np.float64)
        b1 = np.asarray(z["b1"], dtype=np.float64)
        W2 = np.asarray(z["W2"], dtype=np.float64)
        b2 = np.asarray(z["b2"], dtype=np.float64)
    S = int(cfg["n_states"])
    A = int(cfg["n_actions"])
    T = int(cfg["horizon"])
    E = int(cfg["episodes"])
    rng = np.random.default_rng(int(cfg["seed"]))
    R = rng.integers(0, 4, size=(S, A)).astype(np.float64) / 3.0
    starts = rng.integers(0, S, size=E)

    episode_rewards = []
    for e in range(E):
        s = int(starts[e])
        total = 0.0
        for _ in range(T):
            obs = np.zeros(S, dtype=np.float64)
            obs[s] = 1.0
            h = np.tanh(W1 @ obs + b1)
            logits = W2 @ h + b2
            a = int(np.argmax(logits))  # ties -> lowest action index
            total += float(R[s, a])
            s = (s + a + 1) % S
        episode_rewards.append(total)
    mean_reward = float(np.sum(episode_rewards) / (E * T))
    return cfg, episode_rewards, mean_reward


def run_agent(program, casedir, out_path):
    """Run the deliverable; returns (ok, payload). Never raises."""
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, program, casedir, out_path],
            capture_output=True, text=True, timeout=240,
        )
    except Exception as e:
        return False, "run raised %r" % e
    if r.returncode != 0:
        return False, "exit %d: %s" % (r.returncode, (r.stderr or "")[-300:])
    if not os.path.exists(out_path):
        return False, "no output file written"
    try:
        with open(out_path) as fh:
            return True, json.load(fh)
    except Exception as e:
        return False, "output unreadable: %r" % e


def check_case(program, casedir, results):
    """Runs the deliverable twice and validates both reports against the
    independent reference. Appends FAIL lines to results."""
    tag = os.path.basename(casedir.rstrip("/")) or casedir
    if not os.path.isfile(program):
        results.append("FAIL %s: missing program %s" % (tag, program))
        return

    ok1, pay1 = run_agent(program, casedir, "/tmp/opal_fathom_run1.json")
    ok2, pay2 = run_agent(program, casedir, "/tmp/opal_fathom_run2.json")
    if not ok1:
        results.append("FAIL %s: run1 %s" % (tag, pay1))
        return
    if not ok2:
        results.append("FAIL %s: run2 %s" % (tag, pay2))
        return
    if not isinstance(pay1, dict) or not isinstance(pay2, dict):
        results.append("FAIL %s: report is not a JSON object" % tag)
        return

    missing = [k for k in REQUIRED_KEYS if k not in pay1]
    if missing:
        results.append("FAIL %s: missing keys %s" % (tag, missing))
        return

    # determinism: the two runs must agree exactly on the reported metrics
    for k in ("case_id", "seed", "episodes", "horizon", "mean_reward",
              "episode_rewards", "total_steps"):
        if pay1.get(k) != pay2.get(k):
            results.append("FAIL %s: nondeterministic %r (%r vs %r)"
                           % (tag, k, pay1.get(k), pay2.get(k)))

    cfg, ref_ep, ref_mean = reference_rollout(casedir)

    if pay1["case_id"] != cfg["case_id"]:
        results.append("FAIL %s: case_id %r != %r"
                       % (tag, pay1["case_id"], cfg["case_id"]))
    if int(pay1["seed"]) != int(cfg["seed"]):
        results.append("FAIL %s: seed mismatch" % tag)
    if int(pay1["episodes"]) != int(cfg["episodes"]) or \
            int(pay1["horizon"]) != int(cfg["horizon"]):
        results.append("FAIL %s: episodes/horizon mismatch" % tag)
    if int(pay1["total_steps"]) != int(cfg["episodes"]) * int(cfg["horizon"]):
        results.append("FAIL %s: total_steps mismatch" % tag)

    ep = pay1["episode_rewards"]
    if not isinstance(ep, list) or len(ep) != int(cfg["episodes"]):
        results.append("FAIL %s: episode_rewards is not a %d-list"
                       % (tag, cfg["episodes"]))
    else:
        for i, (a, b) in enumerate(zip(ep, ref_ep)):
            try:
                if abs(float(a) - float(b)) > TOL:
                    results.append(
                        "FAIL %s: episode %d reward %r != reference %.6f"
                        % (tag, i, a, b))
                    break
            except Exception:
                results.append("FAIL %s: episode %d reward not numeric"
                               % (tag, i))
                break

    try:
        mr = float(pay1["mean_reward"])
    except Exception:
        results.append("FAIL %s: mean_reward not numeric" % tag)
        return
    if abs(mr - ref_mean) > TOL:
        results.append("FAIL %s: mean_reward %.8f != reference %.8f"
                       % (tag, mr, ref_mean))
        return
    thr = float(cfg.get("min_mean_reward", 0.0))
    if mr < thr - 1e-12:
        results.append("FAIL %s: mean_reward %.6f below release floor %.6f"
                       % (tag, mr, thr))
        return
    results.append("ok %s: mean_reward=%.6f (floor %.6f) deterministic"
                   % (tag, mr, thr))


def main():
    program = "/app/eval_policy.py"
    results = []

    # ---- visible case (agent's own /app outputs must exist too) ----------
    if not os.path.isfile("/app/eval_report.json"):
        results.append("FAIL missing deliverable /app/eval_report.json")
    else:
        try:
            with open("/app/eval_report.json") as fh:
                rep = json.load(fh)
            if not isinstance(rep, dict):
                results.append("FAIL /app/eval_report.json not a JSON object")
            else:
                missing = [k for k in REQUIRED_KEYS if k not in rep]
                if missing:
                    results.append(
                        "FAIL /app/eval_report.json missing keys %s" % missing)
                else:
                    results.append("ok visible deliverable present")
        except Exception as e:
            results.append("FAIL /app/eval_report.json unreadable: %r" % e)

    visible_case = sys.argv[1] if len(sys.argv) > 1 else "/app/case"
    check_case(program, visible_case, results)

    # ---- hidden cases -----------------------------------------------------
    hidden_root = sys.argv[2] if len(sys.argv) > 2 else "/tests/hidden"
    if os.path.isdir(hidden_root):
        cases = sorted(
            os.path.join(hidden_root, d) for d in os.listdir(hidden_root)
            if os.path.isdir(os.path.join(hidden_root, d)))
        if not cases:
            results.append("FAIL no hidden cases present")
        for c in cases:
            check_case(program, c, results)
    else:
        results.append("FAIL hidden root %s missing" % hidden_root)

    failing = [s for s in results if s.startswith("FAIL")]
    for s in results:
        print(s)
    print("RESULT: %s" % ("PASS" if not failing else
                          "FAIL (%d)" % len(failing)))
    return 0 if not failing else 1


if __name__ == "__main__":
    sys.exit(main())
