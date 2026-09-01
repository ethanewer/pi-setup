# quartz-summit — small-scale ML training harness

Write a single executable Python program `/app/train.py`. When you are done, run
it (with no arguments) so it produces the trained artifact `/app/artifact`.
Everything is CPU-only and deterministic. **Do not modify any file already in
`/app`.**

The module must be simultaneously **runnable as a script** and **importable**,
because the verifier re-runs your script on fresh (hidden) inputs and calls
importable functions you leave behind. Hard-code nothing that depends on the
specific words / sizes / goal positions of the shipped fixtures.

## Deliverables

1. `/app/train.py` — the training harness (CLI + importable functions below).
2. `/app/artifact` — created by running `python3 /app/train.py` with no
   arguments against the shipped `/app/corpus.txt` (see CLI contract).

### CLI contract

```
python3 /app/train.py [--train_path P] [--split_path S] [--out O] [--dim D]
```

- `--train_path` : path to a token corpus (default `/app/corpus.txt`).
- `--split_path` : path to a second token file (default `/app/heldout.txt`);
  it is optional — you may read it into the vocabulary or ignore it.
- `--out` : where to write the trained artifact (default `/app/artifact`).
- `--dim` : embedding dimension (default `300`).

The command must end with the trained artifact written at `--out`. **With no
arguments it must train on `/app/corpus.txt` and write `/app/artifact`.** The
verifier re-runs it with `--train_path`/`--split_path`/`--out` pointing at a
different corpus. A corpus is one sentence per line, space-separated tokens;
when tokenizing, lowercase and strip leading/trailing punctuation.

### Artifact format (torch.save dict)

```python
{"words": [str, ...],   # vocabulary in index order
 "vocab_size": int,
 "dim": 300,
 "embed": np.ndarray (V, 300)}   # the trained 300-dim embeddings
```

The verifier loads it with `torch.load(path, weights_only=False)` and `embed`
may be a numpy array or a torch tensor (normalise as needed on your side).

## Importable functions your module MUST expose

```python
def train_embeddings(train_path, out_path, dim=300, ...):
    # train 300-dim embeddings on the corpus, torch.save the artifact dict to
    # out_path, and return that dict. Reuse it from the CLI above.
    ...

def nearest(model, word, k=5):
    # model = the artifact dict; return a list of the k most similar
    # (word, score) pairs to `word` ordered by descending cosine similarity.
    ...

class Environment: ...   # see "Environment" section

def train_policy(env, ...): ...        # train a policy for env
def evaluate_policy(env, policy, trials, horizon): -> float  # mean episode return
def cluster_stability(points, kmin, kmax): -> dict            # {"optimal_k", "stability"}
def eval_sts(model, sts_pairs): -> float                      # cosine-Spearman
```

These are the exact signatures the verifier calls. Keep return types as shown.

## 1) 300-dim embeddings (word2vec-style)

Train a neural model with a `300`-dimension embedding layer per vocabulary word
on the corpus (a skip-gram / negative-sampling word2vec is a fine choice). The
embeddings must capture distributional structure: tokens that co-occur within
the same topical group must end up near each other (the corpus is composed of
coherent topical groups). See `/app/corpus.txt` and `/app/heldout.txt`.

The verifier will:
- re-run your CLI on a **different** corpus and require a `(V, 300)` embed
  matrix,
- for several anchor words, check that the top-4 `nearest()` neighbours include
  at least one other word from the same topical group (i.e. the embedding is
  not random),
- evaluate the `STS` benchmark below and require cosine-Spearman `> 0.70`.

## 2) STS-style evaluation

`/app/sts.json` is a list of records:
```json
{"id": 0, "sentence1": ["t0","t1",...], "sentence2": ["t3","t4",...], "score": 3.7}
```
`sentence1`/`sentence2` are token lists drawn from the same vocabulary as the
corpus; `score` is a 0..5 ground-truth similarity.

`eval_sts(model, sts_pairs)` must: embed each sentence by **mean-pooling** the
(unit-normalised) word vectors, take the cosine similarity between the two
sentence vectors, and return the **Spearman rank correlation** between those
cosine similarities and the `score` labels. A globally thresholded `> 0.70`,
achieved when the embeddings respect the topical structure.

The verifier runs it on `/app/sts.json` with your `/app/artifact`, and again on
a hidden `sts.json` with the embeddings you trained on the hidden corpus.

## 3) Discrete grid environment + RL policy

Implement `Environment` — a 2-D integer grid:

- coordinates `(x, y)` in `{0..size-1}` (side length `size`);
- four cardinal actions `0=(−1,0) N`, `1=(+1,0) S`, `2=(0,−1) W`, `3=(0,+1) E` —
  i.e. `deltas = [(-1,0),(1,0),(0,-1),(0,1)]`, applied as
  `x += dx`, `y += dy`;
- the move is **clipped to the square bounds** (a move that would leave the grid
  stays at the boundary cell);
- after moving, `reward` is an **integer**: `+10` when the euclidean distance
  `sqrt((x-gx)^2+(y-gy)^2)` to the goal `(gx,gy)` is `<= radius` (**inclusive**),
  else `-1`;
- `step(action)` returns `(int(reward), pos, done)` with `done=True` once
  `horizon` steps have been taken; `reset(pos=None)` places the agent at a
  random grid cell (or at `pos`).

Constructor: `Environment(size=12, goal=(8,8), radius=2, horizon=60)`.

`train_policy(env)` → a callable `policy(pos) -> action` (a greedy / value
iteration policy is ideal: enter the reward disc and stay there). The verifier
builds an `Environment` from a config, calls `train_policy`, then
`evaluate_policy(env, policy, trials, horizon)` with **random start cells**, and
requires the **mean episode return** to reach the config's `threshold`. It also
independently recomputes edge cases on your env:
- a move out of bounds via the top/left boundary stays clipped and yields the
  appropriate penalty;
- a step that lands exactly at euclidean distance `radius` gives `+10`
  (inclusive), and a step that lands just beyond gives `-1`.

The visible RL config is `/app/rl_config.json`
(`{"size","goal","radius","horizon","trials","threshold"}`).

## 4) Subsampling-stability clustering

`cluster_stability(points, kmin, kmax)`:
- `points` is a list of 2-D coordinates (numpy array is fine);
- evaluate clustering **stability across random subsamples** for every
  `k` in `[kmin, kmax]` using **prediction strength**: repeatedly split the
  data into two random halves, cluster each half with `k`-means, predict each
  point of the second half with the first half's centroids, and average the
  *min-over-clusters* fraction of within-cluster pairs that stay together;
  average over repetitions → `stability[k]`;
- return `{"optimal_k": int, "stability": {k: float}}` where `optimal_k` is the
  **largest `k` in `[kmin, kmax]` whose `stability[k] >= 0.85`** (fall back to
  `kmin` if none qualify).

On well-separated Gaussian-blob data this recovers the true cluster count: the
stability stays high for `k` up to the true count and drops below the threshold
for larger `k` (over-splitting is inconsistent). The verifier checks
`optimal_k == true_k` for `/app/cluster.json` and for two hidden datasets. Keep
`kmin >= 2` in all provided inputs.

## Constraints

- Write outputs only under `/app`; do not modify the `/app` fixtures.
- CPU-only; keep training small enough to finish in a few minutes.
- Determinism is not graded but helps you debug.
- A short completion message on stdout is fine.
- You may use the installed libraries: `torch`, `numpy`, `scipy`,
  `scikit-learn` (no network access needed).
