#!/usr/bin/env python3
"""quartz-summit verifier.

Modes:
  main    -- validate the agent's /app/artifact (dim 300, nearest-neighbour
             sanity, main STS spearman, main cluster optimal-k, visible RL
             policy reward + Environment edge cases).
  hidden  -- re-run the left-behind /app/train.py harness on hidden fixtures:
             retrain embeddings on a different corpus (interface + 300-dim +
             neighbours + STS spearman), train the RL policy on a different
             environment config (reward + step edge cases), and run
             cluster_stability on two hidden datasets (optimal-k == true k).

Exit 0 => all checks in the mode passed; non-zero => failed.
"""
import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, "/app")
import train

STS_MIN = 0.70
DIM = 300

VIS_TOPICS = {
    "cat": "animals", "apple": "fruits", "hammer": "tools",
    "crimson": "colors", "matrix": "math", "storm": "weather",
}
VIS_DICT = {
    "animals": ["cat", "dog", "fox", "wolf", "bear", "lion", "tiger", "deer", "horse", "rabbit"],
    "fruits": ["apple", "pear", "plum", "berry", "grape", "peach", "melon", "fig", "olive", "guava"],
    "tools": ["hammer", "saw", "wrench", "chisel", "clamp", "pliers", "drill", "file6", "plane", "lathe"],
    "colors": ["crimson", "azure", "amber", "emerald", "violet", "scarlet", "indigo", "taupe", "ochre", "beige"],
    "math": ["matrix", "vector", "scalar", "tensor", "gradient", "kernel", "basis", "manifold", "covariance", "eigenvalue"],
    "weather": ["rain", "snow", "storm", "cloud", "breeze", "frost", "thunder", "shower", "drizzle", "blizzard"],
}
HID_TOPICS = {
    "robin": "birds", "carrot": "vegetables", "copper": "metals",
    "circle": "shapes", "volt": "units", "ridge": "terrain",
}
HID_DICT = {
    "birds": ["robin", "sparrow", "crow", "hawk", "owl", "finch", "starling", "lapwing", "wren", "gull"],
    "vegetables": ["carrot", "onion", "leek", "radish", "celery", "turnip", "kale", "okra", "chard", "squash"],
    "metals": ["copper", "zinc", "nickel", "cobalt", "brass", "steel", "bronze", "iron", "tin", "lead"],
    "shapes": ["circle", "square", "torus", "dodecahedron", "ellipse", "prism", "cone", "hexagon", "arc", "disk"],
    "units": ["volt", "ampere", "ohm", "henry", "farad", "watt", "joule", "kelvin", "pascal", "lumen"],
    "terrain": ["ridge", "canyon", "valley", "butte", "mesa", "gorge", "plateau", "bluff", "defile", "gorge2"],
}


def load_artifact(path):
    import torch
    d = torch.load(path, map_location="cpu", weights_only=False)
    if isinstance(d.get("embed"), torch.Tensor):
        d["embed"] = d["embed"].numpy()
    return d


def neighbour_ok(art, topics, word_dict):
    ok = True
    for anchor, topic in topics.items():
        nbs = train.nearest(art, anchor, 4)
        words = [w for w, _ in nbs]
        if not any((w != anchor and w in word_dict[topic]) for w in words):
            print(f"  FAIL neighbours for '{anchor}': {words}", file=sys.stderr)
            ok = False
    return ok


def run_rl_checks(cfg):
    env = train.Environment(size=cfg["size"], goal=tuple(cfg["goal"]),
                            radius=cfg["radius"], horizon=cfg["horizon"])
    policy = train.train_policy(env)
    if not callable(policy):
        print("  FAIL train_policy did not return a callable policy", file=sys.stderr)
        return False
    mean = train.evaluate_policy(env, policy, cfg["trials"], cfg["horizon"])
    ok = mean >= cfg["threshold"]
    print(f"  RL mean return {mean:.2f} vs threshold {cfg['threshold']} -> {'OK' if ok else 'FAIL'}")
    # Environment edge cases (independently recomputed).
    S, (gx, gy), r = cfg["size"], tuple(cfg["goal"]), cfg["radius"]
    # boundary: N from (0,0) stays clipped
    env.reset(pos=[0, 0]); rw, pos, _ = env.step(0)
    ok = ok and rw == -1 and pos == (0, 0)
    # boundary: S from (S-1,0) stays clipped
    env.reset(pos=[S - 1, 0]); rw, pos, _ = env.step(1)
    ok = ok and rw == -1 and pos == (S - 1, 0)
    # inclusive radius: move +x onto (gx+r,gy), euclidean distance == r -> +10
    env.reset(pos=[gx + r - 1, gy]); rw, pos, _ = env.step(1)
    d = float(np.hypot(pos[0] - gx, pos[1] - gy))
    ok = ok and rw == 10 and abs(d - r) < 1e-9
    # just outside: move +x from (gx+r,gy) to (gx+r+1,gy), distance r+1 -> -1
    env.reset(pos=[gx + r, gy]); rw, pos, _ = env.step(1)
    d = float(np.hypot(pos[0] - gx, pos[1] - gy))
    ok = ok and rw == -1 and abs(d - (r + 1)) < 1e-9
    if not ok:
        print("  FAIL RL Environment edge cases", file=sys.stderr)
    return ok


def mode_main():
    ok = True
    if not os.path.exists("/app/artifact"):
        print("  FAIL /app/artifact missing", file=sys.stderr)
        return 1
    art = load_artifact("/app/artifact")
    emb = np.asarray(art["embed"], dtype=np.float64)
    if emb.ndim != 2 or emb.shape[1] != DIM:
        print(f"  FAIL embedding dim {emb.shape} != 300", file=sys.stderr)
        ok = False
    else:
        print(f"  embed dim OK {emb.shape}")
    ok = neighbour_ok(art, VIS_TOPICS, VIS_DICT) and ok
    with open("/app/sts.json") as fh:
        pairs = json.load(fh)
    rho = train.eval_sts(art, pairs)
    print(f"  main STS spearman {rho:.4f} (need > {STS_MIN})")
    ok = ok and rho > STS_MIN
    with open("/app/cluster.json") as fh:
        cj = json.load(fh)
    res = train.cluster_stability(cj["points"], cj["kmin"], cj["kmax"])
    print(f"  main cluster optimal_k={res['optimal_k']} (need {cj['true_k']})")
    ok = ok and res["optimal_k"] == cj["true_k"]
    with open("/app/rl_config.json") as fh:
        cfg = json.load(fh)
    ok = run_rl_checks(cfg) and ok
    return 0 if ok else 1


def mode_hidden():
    ok = True
    base = "/tests/hidden"
    # h1_w2v: retrain via the train.py CLI on a different corpus.
    hid = os.path.join(base, "h1_w2v")
    out = "/tmp/qz_hidden_artifact.pt"
    if os.path.exists(out):
        os.remove(out)
    cmd = [sys.executable, "/app/train.py",
           "--train_path", os.path.join(hid, "corpus.txt"),
           "--split_path", os.path.join(hid, "corpus.txt"),
           "--out", out, "--dim", "300"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out):
        print("  FAIL train.py retrain on hidden corpus", file=sys.stderr)
        print(r.stderr[-2000:], file=sys.stderr)
        return 1
    art = load_artifact(out)
    emb = np.asarray(art["embed"], dtype=np.float64)
    if emb.ndim != 2 or emb.shape[1] != DIM:
        print(f"  FAIL hidden embed dim {emb.shape} != 300", file=sys.stderr)
        ok = False
    else:
        print(f"  hidden embed dim OK {emb.shape}")
    ok = neighbour_ok(art, HID_TOPICS, HID_DICT) and ok
    with open(os.path.join(hid, "sts.json")) as fh:
        pairs = json.load(fh)
    rho = train.eval_sts(art, pairs)
    print(f"  hidden STS spearman {rho:.4f} (need > {STS_MIN})")
    ok = ok and rho > STS_MIN

    # h2_rl: different environment config.
    with open(os.path.join(base, "h2_rl", "config.json")) as fh:
        cfg = json.load(fh)
    ok = run_rl_checks(cfg) and ok

    # h3_cluster: two datasets with known cluster counts.
    for fn, expected in (("cluster_k4.json", 4), ("cluster_k2.json", 2)):
        with open(os.path.join(base, "h3_cluster", fn)) as fh:
            cj = json.load(fh)
        res = train.cluster_stability(cj["points"], cj["kmin"], cj["kmax"])
        okk = res["optimal_k"] == cj["true_k"]
        print(f"  hidden {fn}: optimal_k={res['optimal_k']} (need {cj['true_k']}) -> {'OK' if okk else 'FAIL'}")
        ok = ok and okk

    return 0 if ok else 1


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "main"
    rc = mode_main() if mode == "main" else mode_hidden()
    sys.exit(rc)
