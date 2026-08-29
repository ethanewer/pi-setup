# Elm-Terrace: fit, tune, and publish a tiny causal model under a byte budget

Your job: build a **model artifact tuning** pipeline for a small
**causal (autoregressive-style) network**, then validate it end-to-end in this
CPU-only container. Everything runs on CPU; there is no GPU device here.

You only see your own container. After you finish, the verifier inspects every
artifact you leave under `/app` and — crucially — **re-runs
`/app/reconstruct.py`'s `load` subcommand on hidden state dicts** (architectures
it never saw) to prove your reconstructor generalizes instead of only matching
the one committed model.

## Fixed inputs (read-only)

| Path                         | Contents                                                        |
|------------------------------|-----------------------------------------------------------------|
| `/opt/causal/data/state_dict.pt` | a torch state dict of a tiny causal-style network            |
| `/opt/causal/data/train.csv`     | header line `A,B,C,D,E,F,G,Y` then 300 data rows             |
| `/opt/causal/data/holdout.csv`   | header line `A,B,C,D,E,F,G,Y` then **100** data rows (out-of-sample) |

Each CSV row has **8 columns**: numeric features `A,B,C,D,E,F,G` in `[0,1]`
followed by the numeric target `Y`. Fit on `train.csv`; the 100 rows of
`holdout.csv` are your out-of-sample rows — never fit on them.

## Installed toolchain

`numpy`, `scipy`, `pandas`, CPU-only `torch`, and `triton==3.4.0` are already
installed (via a corporate CA proxy). Use **Triton in CPU interpreter mode** by
setting `TRITON_INTERPRET=1`; with no GPU device this is the only way a
`@triton.jit` kernel can run here. Confirm the version with `triton.__version__`.

## What you must do

### 1. `/app/reconstruct.py` — reconstruct & instantiate from a state dict

CLI subcommand:

```bash
python3 reconstruct.py load <state_dict.pt> <out.pt>
```

- Reconstruct the architecture **purely from the state dict's keys and shapes**
  (no extra config exists) and build the `torch.nn.Module`, then
  `model.load_state_dict(state, strict=True)`.
- The file stores the dict either as a bare `{tensor_name: tensor}` mapping, or
  wrapped under a single key like `{"d": {...tensors...}}`. Handle both.
- Contract for the architecture family (this is the *only* thing to assume):
  keys are `fcs.<i>.weight` / `fcs.<i>.bias` for `i in 0..blocks-1`, and
  `head.weight` / `head.bias`. Each block is a `Linear` + ReLU; `head` is the
  final output `Linear`. From shapes: input dim = first axis of `fcs.0.weight`;
  hidden dim = second axis of `fcs.0.weight` (identical across all blocks);
  output dim = first axis of `head.weight`; `blocks` = number of `fcs` layers.
  Infer all of these from *the file every time* — hidden inputs vary them.
- Save `{"arch": {...}, "state_dict": <loaded state>}` into `<out.pt>`, print
  the arch as one JSON line, and exit `0` iff the strict load had zero errors.
  The arch dict has exactly the keys `input`, `hidden`, `head`, `blocks` (the
  JSON numbers inferred above); `<loaded state>` is the bare `{tensor_name:
  tensor}` mapping (unwrapped, as used for the strict load).
- On a malformed / un-upcastable state dict print an error to stderr and exit
  non-zero.

### 2. Fit and publish the tuned (intervened) model (run)

```python
python3 /app/reconstruct.py run
```

Runs the full publish pipeline against the fixtures under `/opt/causal/data/`
and leaves every artifact below under `/app`:

- `/app/model/state_dict.pt`&nbsp;— reconstructed base weights.
- `/app/model/adapter_config.json`&nbsp;— the LoRA adapter config, with
  exactly `"r": 2`, `"lora_alpha": 8` (scale `alpha/r = 4`), `"bias": "none"`,
  `"task_type": "CAUSAL_LM"`, `"target_modules": ["fc0","fc1"]`,
  `"base_model_name_or_path": "elm-terrace-tiny-causal"`, and
  `"inference_mode": true`.
- `/app/model/arch.json`&nbsp;— the arch dict from reconstruction.

Train rank-2 LoRA adapters on the two intervenable `Linear` blocks (`fc0`,
`fc1`) and the head, using `train.csv`, so the tuned model's out-of-sample error
clearly beats the untuned base model. Keep **the entire serialized model**
(all files under `/app/model/`) at or under **100,000 bytes total**.

### 3. `/app/lowrank.npz` — the low-rank factors

Compressed `npz` with keys exactly `U_fc0,V_fc0,U_fc1,V_fc1,U_head,V_head`,
shapes `(out,r)`, `(r,in)`. Each `U@V` must have rank `<= r = 2`.

### 4. `/app/preds.csv` — out-of-sample predictions

Header line `prediction`, then exactly one float per holdout row — so
**101 lines total** (header + 100). No index column.

### 5. `/app/sample.csv` — dataset sampled from the intervened model

Header line `A,B,C,D,E,F,G,Y`, then exactly **1000 data rows**. Draw the
features `A..G` (each in `[0,1]`) from the prior you used and set `Y =
model(features)`. Columns must keep the original order `A,B,C,D,E,F,G,Y`.

### 6. `/app/triton_cpu.py` + `/app/lt_triton_result.json` — Triton on CPU

Write a standalone Triton script that:

- sets `TRITON_INTERPRET=1` (or is run with it set),
- defines a `@triton.jit` elementwise kernel that computes `o = x*g + x*x`,
- launches it through the interpreter path on a small CPU tensor,
- checks the result against a reference torch computation,
- writes `/app/lt_triton_result.json` = `{"match": true, ...}` and exits `0`
  on success (non-zero otherwise). Confirm `triton.__version__` as well.

## Determinism &mdash optional but recommended

Set fixed seeds (`torch.manual_seed(0)`, `numpy.random.seed(0)`) so your outputs
are reproducible. It will not be required for scoring but keeps things stable.

## Constraints

- No GPU, no CUDA device calls. Use Triton interpreter mode only.
- The committed `/opt/causal/data/*` are read-only; leave them untouched.
- Do not install extra packages; the installed stack suffices.
- `reconstruct.py` must be a real, general reconstructor (works on any dict in
  the family), not a hardcoded single case.

## Success criteria (verifier)

When done, the verifier confirms: all deliverables above exist; `load` succeeds
on the committed and every hidden state dict and reproduces them exactly;
the model dir is <= 100,000 bytes; the adapter config carries the exact LoRA
fields; low-rank and CSV schemas match; and the Triton script runs interpretively
with `match: true`. Produce everything and leave it under `/app`. Good luck.