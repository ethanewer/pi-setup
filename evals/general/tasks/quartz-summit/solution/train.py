#!/usr/bin/env python3
"""
quartz-summit — one small-scale ML training harness.

Produces a 300-dimensional word-embedding artifact, a trained reinforcement
learning policy for a discrete grid environment, a subsampling-stability
clustering selector, and an STS-style similarity evaluation. CPU only.

CLI:
  python3 /app/train.py \
      --train_path <corpus> --split_path <split> --out <model.pt>
  (no args -> train on /app/corpus.txt, write /app/artifact)

The same module is importable so the verifier can call train_embeddings,
Environment / train_policy / evaluate_policy, cluster_stability and eval_sts.
Everything is seeded and deterministic.
"""
import argparse
import json
import math
import os
import random
import re
import sys

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

# ---------------------------------------------------------------------------
# tokens / corpus helpers
# ---------------------------------------------------------------------------
_WORD_RE = re.compile(r"[^0-9A-Za-z]+")


def tokenize(line):
    """Lower-case a sentence line into a list of tokens."""
    return [t for t in _WORD_RE.sub(" ", line.lower()).split() if t]


def _read_lines(path):
    with open(path, "r", encoding="utf-8") as fh:
        for ln in fh:
            ln = ln.strip()
            if ln:
                yield ln


# ---------------------------------------------------------------------------
# 1) word2vec-style embeddings (300-dim) on CPU
# ---------------------------------------------------------------------------
class SkipGram(nn.Module):
    def __init__(self, vocab_size, dim):
        super().__init__()
        self.embed = nn.Embedding(vocab_size, dim)
        self.embed.weight.data.normal_(0.0, 0.1)

    def forward(self):
        return self.embed.weight


def _build_pairs(sentences, w2i, window=2, neg=10, rng=None):
    vocab = list(w2i)
    V = len(vocab)
    centers, ctxs = [], []
    for s in sentences:
        for i, w in enumerate(s):
            c = w2i[w]
            for j in range(max(0, i - window), min(len(s), i + window + 1)):
                if i == j:
                    continue
                centers.append(c)
                ctxs.append(w2i[s[j]])
    return centers, ctxs, V


def train_embeddings(train_path, out_path, dim=300, epochs=50, window=2,
                     neg=10, seed=0):
    """Train 300-dim embeddings on a token corpus and save the artifact.

    Artifact (torch.save dict):
      { "words": list[str], "vocab_size": int, "dim": int,
        "embed": np.ndarray (V,dim), "train_path": str }
    Returns that dict.
    """
    torch.manual_seed(seed)
    np.random.seed(seed)
    random.seed(seed)
    rng = np.random.default_rng(seed)

    sentences = [tokenize(ln) for ln in _read_lines(train_path)]
    sentences = [s for s in sentences if s]
    vocab = []
    seen = set()
    for s in sentences:
        for w in s:
            if w not in seen:
                seen.add(w)
                vocab.append(w)
    w2i = {w: i for i, w in enumerate(vocab)}
    V = len(vocab)
    if V == 0:
        raise ValueError("empty vocabulary")

    centers, ctxs, V = _build_pairs(sentences, w2i, window=window, neg=neg)
    centers = np.array(centers, dtype=np.int64)
    ctxs = np.array(ctxs, dtype=np.int64)
    npairs = len(centers)

    model = SkipGram(V, dim)
    opt = torch.optim.Adam(model.parameters(), lr=0.03)
    bs = 256
    for _ in range(epochs):
        perm = rng.permutation(npairs)
        for st in range(0, npairs, bs):
            idx = perm[st:st + bs]
            c = torch.from_numpy(centers[idx])
            t = torch.from_numpy(ctxs[idx])
            opt.zero_grad()
            vc = model.embed(c)
            vt = model.embed(t)
            pos = F.logsigmoid((vc * vt).sum(1))
            ns = torch.from_numpy(rng.integers(0, V, size=(len(idx), neg)))
            neg_loss = F.logsigmoid(-(vc.unsqueeze(1).expand(-1, neg, dim)
                                      * model.embed(ns)).sum(2))
            loss = -(pos.mean() + neg_loss.mean())
            loss.backward()
            opt.step()

    embed = model.embed.weight.detach().numpy().astype(np.float32)
    art = {"words": vocab, "vocab_size": int(V), "dim": int(dim),
           "embed": embed, "train_path": str(train_path)}
    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    torch.save(art, out_path)
    return art


def _load_art(path):
    d = torch.load(path, map_location="cpu", weights_only=False)
    if isinstance(d.get("embed"), torch.Tensor):
        d["embed"] = d["embed"].numpy()
    return d


def nearest(model, word, k=5):
    """Return the k nearest words to `word` by cosine similarity."""
    words = model["words"]
    embed = np.asarray(model["embed"], dtype=np.float64)
    wi = words.index(word)
    w = embed[wi]
    n = np.linalg.norm(w)
    if n == 0:
        return []
    sims = (embed @ w) / (np.linalg.norm(embed, axis=1) * n + 1e-12)
    order = np.argsort(-sims)[:k]
    return [(words[i], float(sims[i])) for i in order]


# ---------------------------------------------------------------------------
# 2) discrete grid environment with boundary clipping + goal radius reward
# ---------------------------------------------------------------------------
class Environment:
    """Integer grid of side `size` (coords 0..size-1). Actions are 4 cardinal
    moves: 0=N(-1,0) 1=S(+1,0) 2=W(0,-1) 3=E(0,+1). Each step gives +10 when
    the euclidean distance to `goal` <= `radius` (inclusive) else -1. The move
    is clipped to the square [[0,size-1]^2]. reward is always an integer.
    """

    GOAL_REWARD = 10
    STEP_PENALTY = -1

    def __init__(self, size=12, goal=(8, 8), radius=2, horizon=60):
        self.size = int(size)
        self.goal = (int(goal[0]), int(goal[1]))
        self.radius = int(radius)
        self.horizon = int(horizon)
        self.deltas = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        self.pos = None
        self.steps = 0

    def reset(self, pos=None, rng=None):
        if pos is None:
            rr = rng if rng is not None else np.random.default_rng()
            self.pos = (int(rr.integers(0, self.size)),
                        int(rr.integers(0, self.size)))
        else:
            self.pos = tuple(int(v) for v in pos)
        self.steps = 0
        return self.pos

    def _clip(self, x, y):
        return (min(self.size - 1, max(0, x)),
                min(self.size - 1, max(0, y)))

    def step(self, action):
        dx, dy = self.deltas[int(action)]
        x, y = self._clip(self.pos[0] + dx, self.pos[1] + dy)
        self.pos = (x, y)
        self.steps += 1
        d = math.hypot(x - self.goal[0], y - self.goal[1])
        reward = self.GOAL_REWARD if d <= self.radius else self.STEP_PENALTY
        done = self.steps >= self.horizon
        return int(reward), self.pos, done


def train_policy(env, gamma=0.99, iters=300):
    """Return a callable policy(pos) -> action via value iteration over the
    finite grid (documented contract: a single callable, not a tuple)."""
    S = env.size
    V = np.zeros((S, S), dtype=np.float64)
    A = np.zeros((S, S), dtype=np.int64)
    gx, gy = env.goal
    for _ in range(iters):
        Vn = V.copy()
        for i in range(S):
            for j in range(S):
                best = -1e18
                ba = 0
                for a, (dx, dy) in enumerate(env.deltas):
                    ni = min(S - 1, max(0, i + dx))
                    nj = min(S - 1, max(0, j + dy))
                    d = math.hypot(ni - gx, nj - gy)
                    r = env.GOAL_REWARD if d <= env.radius else env.STEP_PENALTY
                    val = r + gamma * V[ni, nj]
                    if val > best:
                        best = val
                        ba = a
                Vn[i, j] = best
                A[i, j] = ba
        V = Vn

    def policy(pos):
        i, j = int(pos[0]), int(pos[1])
        return int(A[i, j])

    return policy


def evaluate_policy(env, policy, trials=60, horizon=60, seed=0):
    rng = np.random.default_rng(seed)
    tot = 0.0
    for _ in range(trials):
        env.reset(rng=rng)
        ep = 0.0
        s = 0
        while s < horizon:
            a = policy(env.pos)
            r, _, done = env.step(a)
            ep += r
            s += 1
            if done:
                break
        tot += ep
    return tot / trials


# ---------------------------------------------------------------------------
# 3) subsampling-stability clustering (prediction strength)
# ---------------------------------------------------------------------------
def _prediction_strength(points, k, B=24, seed=0):
    from sklearn.cluster import KMeans
    rng = np.random.default_rng(seed)
    n = len(points)
    vals = []
    for _ in range(B):
        perm = rng.permutation(n)
        h = n // 2
        A = points[perm[:h]]
        BB = points[perm[h:]]
        kmA = KMeans(k, n_init=5, random_state=int(rng.integers(0, 10 ** 9)))
        kmA.fit(A)
        kmB = KMeans(k, n_init=5, random_state=int(rng.integers(0, 10 ** 9)))
        kmB.fit(BB)
        predA = kmA.predict(BB)
        labB = kmB.labels_
        minl = 1.0
        for l in range(k):
            ii = np.where(labB == l)[0]
            if len(ii) < 2:
                continue
            pr = predA[ii]
            same = 0
            tot = 0
            for x in range(len(ii)):
                px = pr[x]
                for y in range(x + 1, len(ii)):
                    tot += 1
                    same += int(px == pr[y])
            if tot > 0:
                minl = min(minl, same / tot)
        vals.append(minl)
    return float(np.mean(vals))


def cluster_stability(points, kmin, kmax, threshold=0.85, seed=0):
    """Prediction-strength stability across random subsample halves.

    For each k in [kmin,kmax] the data is repeatedly split in two, both halves
    are clustered with k-means, and the min-over-clusters agreeance of
    within-cluster pairs (predicted by the other half's centroids) is averaged.
    optimal_k = the largest k whose stability stays >= `threshold` (>= kmin).
    Returns {"optimal_k": int, "stability": {k: float}}.
    """
    pts = np.asarray(points, dtype=np.float64)
    stability = {}
    for k in range(int(kmin), int(kmax) + 1):
        stability[k] = _prediction_strength(pts, k, seed=seed * 10 + k)
    best = int(kmin)
    for k in stability:
        if stability[k] >= threshold:
            best = k
    return {"optimal_k": int(best), "stability": stability}


# ---------------------------------------------------------------------------
# 4) STS-style evaluation (mean-pooled cosine -> spearman)
# ---------------------------------------------------------------------------
def _sent_emb(embed, words, w2i, toks):
    idxs = [w2i[t] for t in toks if t in w2i]
    if not idxs:
        return None
    v = embed[idxs].mean(axis=0)
    n = np.linalg.norm(v)
    return v / n if n else v


def eval_sts(model, sts_pairs):
    """sts_pairs: list of {"sentence1":[...], "sentence2":[...], "score":float}.
    Returns the cosine-Spearman float using mean-pooled embeddings."""
    from scipy.stats import spearmanr
    words = model["words"]
    embed = np.asarray(model["embed"], dtype=np.float64)
    w2i = {w: i for i, w in enumerate(words)}
    preds = []
    labels = []
    for p in sts_pairs:
        e1 = _sent_emb(embed, words, w2i, p["sentence1"])
        e2 = _sent_emb(embed, words, w2i, p["sentence2"])
        if e1 is None or e2 is None:
            continue
        preds.append(float(np.dot(e1, e2)))
        labels.append(float(p["score"]))
    if len(preds) < 5:
        return 0.0
    rho, _ = spearmanr(preds, labels)
    return float(rho)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train_path", default="/app/corpus.txt")
    ap.add_argument("--split_path", default="/app/heldout.txt")
    ap.add_argument("--out", default="/app/artifact")
    ap.add_argument("--dim", type=int, default=300)
    args = ap.parse_args()

    art = train_embeddings(args.train_path, args.out, dim=args.dim)
    print(f"trained {art['vocab_size']}x{art['dim']} embeddings -> {args.out}",
          flush=True)
    # optional validation passes over the visible sensors (not required)
    if os.path.exists("/app/sts.json"):
        with open("/app/sts.json") as fh:
            pairs = json.load(fh)
        rho = eval_sts(art, pairs)
        print(f"main STS spearman: {rho:.4f}", flush=True)
    if os.path.exists("/app/cluster.json"):
        with open("/app/cluster.json") as fh:
            cj = json.load(fh)
        res = cluster_stability(cj["points"], cj["kmin"], cj["kmax"])
        print(f"main cluster optimal_k={res['optimal_k']}", flush=True)


if __name__ == "__main__":
    main()
