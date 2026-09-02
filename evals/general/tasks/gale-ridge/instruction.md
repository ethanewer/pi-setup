# Gale Ridge — offline model-serve pipeline

Gale Ridge serves an internal **bag-of-tokens** model completely offline. You must
author one self-contained Python program, `/app/workflow.py`, that carries the
whole serve lifecycle end to end and leaves a verified artifact pack in
`/app/artifact`. The verifier will **re-run your program** on the committed config
and on hidden configs, and it will independently inspect every artifact and the
running ML-flow server — so every path below is mandatory.

## Deliverables (exact paths)

1. `/app/workflow.py` — an executable, dependency-free-args Python 3 program that
   does the real work described below (import `torch`/`mlflow` are fine; it must
   never `cat` a precomputed answer).
2. `/app/artifact/` — a directory your program produces, containing at least:
   `report.json`, `shapes_trace.json`, `BagNet.pt`, `seqhead.pt`, `reload_pred.json`.

Everything the verifier checks it recomputes itself; your `report.json` is the
canonical record your program must fill in truthfully.

## Command-line contract

```
python3 /app/workflow.py [--config PATH] [--out DIR] [--check-artifact PATH]
```

- `--config PATH` — read the run config from `PATH`. Default `/app/config.json`.
- `--out DIR` — write artifacts into `DIR`. Default `/app/artifact`.
- `--check-artifact PATH` — do **not** run the pipeline; only test whether `PATH`
  can be loaded as a gale-ridge `BagNet` state dict. Write a single JSON object
  `{"load_ok": true|false, "path": "<PATH>"}` into `DIR/check_artifact.json`
  (`DIR` = `--out` or `/app/artifact`) and exit `0` in **both** cases.

Default invocation is `python3 /app/workflow.py`.

## The config schema

```json
{
  "num_examples": 1000,
  "batch_sizes": [128, 96],
  "cap": 3,
  "num_labels": 7,
  "min_params": 600,
  "width_letter": "A",
  "levers": ["B", "C", "D"],
  "epochs": 3,
  "eval_batch": 64,
  "mlflow_port": 8080,
  "seed": 20240817
}
```

Fields your pipeline must honour:

- `num_examples` — number of synthetic training examples to generate.
- `batch_sizes` / `eval_batch` — candidate batch sizes your trainer may use.
- `cap` — **maximum** number of distinct `(batch_size, feature_dim)` shape pairs
  the pipeline may ever feed to a forward pass (see §Shape budget).
- `num_labels` — custom head output count (§Reconfigured head).
- `min_params` — minimum combined parameter count for the encoder+classifier pair
  (§Initialisation adequacy).
- `width_letter`, `levers` — the capacity-experiment answer letters (§Capacity).
- `epochs`, `seed` — trainer knobs (seed must be used for reproducibility).
- `mlflow_port` — port the ml-flow server must listen on.

If the JSON is malformed or a field has the wrong type, your program **must not
crash**: fall back to the defaults above, keep going, and still produce a full
`report.json`.

## The served model architecture

The served network `BagNet` is exactly:

```
instance_encoder: Linear(feature=784, hidden=10)
bag_classifier:   Linear(hidden=10, out=10)
```

So the loadable state dict has exactly the keys and **fixed** shapes:

```
instance_encoder.weight  (10, 784)     instance_encoder.bias  (10,)
bag_classifier.weight    (10, 10)      bag_classifier.bias    (10,)
```

`feature` is always `784` (from the frozen weights) — do not read it from config.

## Steps your program must perform

### 1. Offline cache + tokenizer
A build-time "vendor" lives at `/app/vendor/` and contains `bagnet_frozen.pt`
(the pretrained state dict above) and `tokens.txt` (a plain token
alphabet across a line). Copy `/app/vendor/*` into a local cache directory
`/app/cache/` (creating it), then load **only from `/app/cache/`** (offline
reuse; never read `/app/vendor` again afterwards). Build a character tokenizer
over the cached vocabulary, save it as `/app/cache/tokenizer.json`, reload it
from that file, and encode→decode the fixed probe text
`"ridge gale ridge gale tide gale call"`, which must round-trip exactly.

### 2. Reconstruct the architecture from the state dict
From the **cached** `bagnet_frozen.pt` reconstruct a `BagNet` whose named
parameter keys and shapes match the dict exactly (a general reconstructor that
infers `feature`, `hidden`, `out` from the shapes, not a hard-coded subset).

### 3. Preserve fixed tensor shapes
During training/serialization below you must **never resize** any parameter.
The (784,10-encoder/10,10-classifier) weights and their (10,) biases must keep
their exact shapes from step 2 through the rest of the pipeline.

### 4. Train with a bounded distinct-shape set
Generate `num_examples` synthetic bags `x ~ N(0,I)` of `feature=784` with integer
labels `y=0.. (from 10 classes)`, then train the reconstructed `BagNet` with the
classifier cross-entropy for `epochs` epochs. Record the `(batch_size, feature)`
of **every** forward pass (train and eval) into a list and, after the run, in
`/app/artifact/shapes_trace.json` as `{"shapes": [[b,f], ...]}`.

**Shape limit:** the number of **distinct** `(b, f)` pairs in that trace must be
**at most `cap`**. So you must actually enforce the cap: pick batch sizes so the
total distinct set stays `<= cap` (e.g. pad an incomplete tail to a full batch
instead of leaving a run off out-of-shape leftover; use an eval shape only when
it fits within the remaining cap budget). This is the hard constraint — a naive
trainer that lets every epoch's remainder become a new shape will blow past `cap`.

### 5. Serialize, reload, re-predict
After training, write `report.json`, `bag` output to `/app/artifact/BagNet.pt`
(each same `state_dict()`), reload it **from that artifact file** with your
reconstructor, and confirm the reloaded model reproduces the in-memory model's
logits on a fixed 3-bag probe (exact equality within 1e-5). Save the probe tensors
and the tag `reload_predicts: true` into `reload_pred.json`.

### 6. Initialise components to adequate size
Report the total parameter count of the encoder+classifier pair
(`instance_encoder` + `bag_classifier` combined). If at least `min_params`,
`init_ok` is true. (With the shapes above this holds trivially; the point is the
program must check and report it.)

### 7. Reconfigure the sequence-classifier head to a custom output count
Build a distinct small `SeqHead` classifier that maps the `(10,)` bag
representation to exactly `num_labels` outputs:

```
SeqHead: nn.Linear(10, num_labels)
```

Save it as `/app/artifact/seqhead.pt` (state dict), reload it, and confirm the
head's weight matrix has `num_labels` rows (report `head_labels`).
> This head is intentionally separate from the frozen `BagNet`; the frozen shapes
> from step 3 must NOT be resized to fit it.

### 8. Capacity-effect mapping (answer letter)
Choose which single scripted edit actually improves model capacity. You must
**run a small measurement** (not look anything up): for each candidate letter
list your program builds the variant `BagNet`, counts its free (trainable)
parameter `P` as the effective capacity proxy, and the answer letter is the one
with the **strictly largest** P. The candidates are:

- `{width_letter}` (default `"A"`) — Hidden-model width is widened (use hidden
  multiplier `4`), which strictly raises capacity.
- each of `levers` (`"B","C","D"`) — the same architecture but with a larger
  step-size / more epochs / re-ordered orientation; none of these changes the
  parameter count, so they do **not** raise capacity.

Record the winning letter as `best_edit` and the per-letter capacities as
`scores`. An agent that traces a lever step/epoch change will pick a non-winning
letter and fail.

### 9. ML-flow tracking server
Ensure an `mlflow` tracking server is serving on `http://127.0.0.1:{mlflow_port}`
(port `8080` by default). If one is already healthy there, reuse it; else start a
background `mlflow server` on that port (`--backend-store-uri sqlite:////app/mlruns.db`)
and wait until `GET /health` returns `200`. Then record a real MLflow run logging
one metric (`accuracy=0.97`) through it and set `mlflow_ok: true` if the write and
the health probe both succeed. The server must keep serving after `workflow.py`
exits (e.g. start it detached).

## `/app/artifact/report.json` schema (must contain exactly these keys)

```json
{
  "offline_load_ok": true|false,
  "tokenizer_roundtrip_ok": true|false,
  "shapes_preserved": true|false,
  "fixed_shapes": {"instance_encoder.weight":[10,784],"instance_encoder.bias":[10],"bag_classifier.weight":[10,10],"bag_classifier.bias":[10]},
  "distinct_shapes": <int>,
  "shapes_cap": <int>,
  "loads_cap_ok": <bool>,
  "reload_predicts": true|false,
  "head_out": <int>,
  "init_params": <int>,
  "init_min": <int>,
  "init_ok": true|false,
  "best_edit": "<letter>",
  "capacities": {<letter>: <int>},
  "mlflow_ok": true|false,
  "mlflow_port": 8080,
  "config_file": "<path>"
}
```

Note fixed_shapes uses shape ordered as the dict serialized by torch:
`instance_encoder.weight` [10,784], `bag_classifier.weight` [10,10], biases [10].

## Edge cases the hidden suite probes

- **`cap=1`**: your batch plan may only ever produce a single distinct shape
  (train and any check must all reuse the same `(b, feature)`).
- **`cap=2` with different `num_labels`**: the distinct-shape budget is `2` and
  the head must expose that `num_labels`.
- **corrupt artifact**: `--check-artifact` on a non-loadable file must report
  `load_ok:false` (exit 0), while `--check-artifact` on a genuinely saved `BagNet.pt`
  reports `load_ok:true`.
- **malformed config**: wrong-typed/missing keys -> no crash; full `report.json`
  written with defaults.

## Non-negotiables

- Do not modify `/app/vendor/**` or read it at runtime (`workflow.py` must consume
  only from `/app/cache/` after materialising).
- Do not touch `/tests/`. The verifier and your oracle never see each other's
  expectations.
- Reproducible: fixed `seed` from config.
- During step 4 only the trained model's parameter **values** change, never
  shapes.

Run `python3 /app/workflow.py` to produce everything and start the ML-flow server.
The verifier re-runs your script and independently checks every invariant and the
live server.