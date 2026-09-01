# prism-hearth — local-weights inference pipeline

You are deployed inside a container that ships, fully offline, a small causal
language model with its tokenizer and a fixed **game-evaluation model** for an
invented strategy game ("Verlokar's Hearth"). No network, no GPU. Your job is
to author **`/app/infer.py`**: a single self-contained Python program that runs
the whole inference pipeline for a scenario and writes a precisely-specified
set of artifacts. It must generalise to *any* scenario conforming to the
schema below, including the hard/malformed edge cases the hidden tests probe.

---

## Shipped immutable assets (DO NOT MODIFY ANY OF THESE)

| path | meaning |
|------|---------|
| `/app/models/verlok_lm/` | local causal LM checkpoint (`config.json` + `model.safetensors`) |
| `/app/tokenizers/verlok_bpe/` | local BPE tokenizer (AutoTokenizer-ready) |
| `/app/weights/hearth_net.pt` | the HearthNet state dict — your **fixed** source weights |
| `/app/job.json` | the visible scenario (shipped example) |
| `/app/folds/…` | bag-feature `.npy` fixtures referenced by the visible job |

These are **read-only resources**. You must load them and never **write**, copy,
or `torch.save` back over them. The verifier checks the weights are still
byte-for-byte identical after your run, and that every tensor has its **fixed
shape preserved** (`enc.weight` = `(10,784)`, `act.weight` = `(10,10)`, biases
`(10,)`). Loading in fp32 CPU is the only legitimate use.

## Deliverables (exactly three)

1. `**/app/infer.py**` — the pipeline program described below (executable).
2. `**/app/loss.txt**` — the final micro-count-rescaled loss (produced by running
   the visible scenario with out dir `/app`).
3. `**/app/batch_plan.json`** — the microbatch plan for the visible scenario.

To emit the deliverables, run once with `OUTDIR=/app`:

```
python3 /app/infer.py /app/job.json /app
```

## Constructions to build

`infer.py` must implement, in this order:

### 1. Local causal LM + tokenizer load with a forward
- Call `AutoTokenizer.from_pretrained("/app/tokenizers/verlok_bpe",
  local_files_only=True)` and
  `AutoModelForCausalLM.from_pretrained("/app/models/verlok_lm",
  local_files_only=True)` (both **load B model + weights** from the directory,
  never reach the network, never leave `device_map="gpu"`).
- On the token id sequence given in the scenario as `prompt_tokens`, run a
  forward pass and compute the mean teacher-forcing cross-entropy `lm_ce`
  (shift-right averaging over all positions except the final). Record it and
  the tokenizer's `vocab_size`.

### 2. HearthNet
Load `/app/weights/hearth_net.pt` (fp32, CPU). It is a lightweight standalone
model you will feed forward without a full torch `nn.Linear` wrapper if you
wish, but the math below is exact and must be reproduced exactly.

```
W1 = state["enc.weight"]   # (10,784)         encoder weight
b1 = state["enc.bias"]     # (10,)
W2 = state["act.weight"]   # (10,10)          gate/classifier weight
b2 = state["act.bias"]     # (10,)
gw = state["gate.w"]       # (10,)
gb = state["gate.b"]       # (1,)
Oc = state["outc.weight"]  # (3,10)
Ob = state["outc.bias"]    # (3,)
```

For a **bag** of instances `X` with shape `(N,784)` the forward is:

```
H    = relu(X @ W1ᵀ + b1)                  # (N,10)   encoder
gate = H @ gw + gb                        # (N,)     per-instance gate logit
att  = softmax(gate)                      # (N,)       attention over bag, sums to 1
mil  = H @ W2ᵀ + b2                       # (N,10)    per-instance move logits
bag  = Σ_i att[i] * H[i]                  # (10,)      attention-weight bag vector
policy = W2 @ bag + b2                    # (10,)      legal-move logits (10 moves)
outc   = Oc @ bag + Ob                    # (3,)       outcome logits (3 outcomes)
probs  = softmax(outc)                    # (3,)       POST-SOFTMAX outcome probabilities
```

Every scenario request contributes **one bag** and one integer **target class
`t` in `0..9`**; the per-request loss is
`CE_i = CrossEntropy(policy,  [t])` (one-hot over the 10 policy logits).

### 3. Microbatch packing (the schedule)
A scenario lists requests in order. Pack them into **microbatches** with this
exact greedy rule (in the request order; `span` per request, default `1`):

```
groups = []; cur=[], cspan=0, ccnt=0
for i, r in enumerate(requests):
    sp = r("span",1)
    if cur and ((cspan+sp > window) or (ccnt >= batch_budget)):
        start a new microbatch (push cur; reset cur,cspan,ccnt)
    cur.append(i); cspan+=sp; ccnt+=1
if cur: push cur
```

An **oversized** single request (`span > window`) still becomes a microbatch of
its own (it is allowed to overflow alone). This grouping must be reproduced
exactly — the verifier recomputes it from the scenario.

### 4. Loss, scaling, gradients (the correctness core)
Let `N` be the total number of requests. For microbatch `m` (its request list
`idxs`, `k_m = len(idxs)`):

- `l_m = mean(average CE over requests in m)` — pooled over the microbatch.
- `scaled_m = l_m * (k_m / N)`.

`scaled_m` is the *microcount-rescaled* share of the final loss. The finished
loss is the sum of the shares:

```
L = Σ_m scaled_m = (1/N) Σ_i CE_i            # the “average over the microbatch”
```

Write this value to `loss.txt` as a bare floating point, formatted
`"%.10e\n"`.

- **AFAB ordering.** Run every microbatch's forward pass first (each producing
  `scaled_m`, keeping its computation graph), then — only after all forwards —
  back-propagate **all of them** (accumulate gradients onto the two trainable
  weights `W1` and `W2`, e.g. by calling `.backward()` on each `scaled_m`),
  so that **no forward pass ever happens after a backward pass**. The verifier
  asserts the recorded global event order is exactly
  `["F0","F1",…,"F{n_mb-1}"]` followed by `["B"]*n_mb`.

### 5. Output files (all written under `OUTDIR`)

`infer.py` is run as `python3 /app/infer.py <JOB.json> <OUTDIR>` and must write
**all** of the following into `OUTDIR`:

| file | content |
|------|---------|
| `loss.txt` | the final `L` above, `%.10e\n` (one float) |
| `batch_plan.json` | `{"microbatches": [[request idx…], …], "order":["F0","F1",…,"B","B",…], "n_microbatches": int, "batch_satisfied": true, "window_satisfied": true}` |
| `heads.json` | the head probe for the **first request of the first microbatch** (see below) |
| `grad.json` | `{"W2_norm": float, "W1_norm": float}` — the accumulated reference gradient norms |
| `lm_head.json` | `{"vocab_size": int, "loss_ce": float, "lm_loaded": true, "tokenizer_loaded": true, "load_error": null, "afib_order_ok": true}` |
| `critical.json` | `{"hearth_net.pt": "<sha256 of the pristine file>"}` |

`heads.json` must contain (for the probe request): `bag_size`
(`N`), `mil_logits_dim` (`10`), `policy_logits` (10 floats),
`outcome_probs` (3 floats, post-softmax), `attention` (`N` floats), and
`outcome_sum` (the sum of `outcome_probs`).

The verifier **executes** `/app/infer.py` on the visible job and on every hidden
scenario (each with a fresh `OUTDIR`) and compares the produced numbers to the
golden reference — so everything must be exact and reproducible to float
tolerance, not merely plausible.

## Scenario (job) schema

```json
{
  "name": "…",
  "batch_budget": <int>,
  "window": <int>,
  "prompt_tokens": [ <int 0..vocab-1>, ... ],
  "requests": [
     {"id": <int>, "feat": "<path to (N,784).npy>", "target": <int 0..9>, "span": <int> },
     ...
  ]
}
```

`feat` is always an absolute path to a `.npy` of shape `(N,784)` float32
(`N >= 1`).

## Edge cases the hidden scenarios will probe (you MUST handle all)

1. **Oversized-sole**: a single request whose `span` exceeds `window` must still
   be given its own microbatch (never silently dropped).
2. **Singleton micros**: `batch_budget=1` → each request is its own microbatch.
3. **Singleton bags / zero-span**: bags with exactly `1` instance (`att` is a
   single 1.0, `#N=1`) and a request with `span=0` (span `0` costs nothing but
   still forms one microbatch).
4. **Large bursts/recycling**: tens of requests across many microbatches; the
   loss, grads and plan must all still exactly match.

## Constraints

- Deliverables: `/app/infer.py`, `/app/loss.txt`, `/app/batch_plan.json`.
  Only these three are checked as deliverables, but `infer.py` may freely write
  the extra artifact files in `OUTDIR`.
- `infer.py` must be executable (`chmod +x`) and always runnable
  `python3 /app/infer.py <JOB> <OUTDIR>` without becoming custom arguments.
- Never modify `/app/weights/hearth_net.pt`, `/app/models/…`,
  `/app/tokenizers/…`, or `/app/job.json`. The verifier hashes/byte-diff uses
  them and asserts the fixed `(10,784)` / `(10,10)` shapes.
- No GPU, no systemd, no network at runtime. Everything must load from local
  files.

When done, run `python3 /app/infer.py /app/job.json /app` so your three
deliverables are real and present in `/app`. Good luck.