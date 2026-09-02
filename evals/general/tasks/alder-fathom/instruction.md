# alder-fathom — replay a trained rover policy under a fixed seed

A planetary rover's navigation policy was trained offline and shipped as a
PyTorch checkpoint. Before it can be certified for deployment, mission control
requires a **deterministic replay evaluation**: the policy must be run against
a seeded telemetry environment and produce a *stable* mean-reward figure — the
same number, to the last bit, on every machine, every run.

Your job is to write ONE program, `/app/evaluate.py`, that performs this
replay, and to run it on the provided case to produce `/app/eval_report.json`.

## Provided fixture (read-only)

Everything you need is under `/app/case/`:

- `/app/case/env_config.json` — the environment descriptor, with keys:
  - `case_id` (string), `seed` (int), `n_trials` (int),
  - `obs_dim`, `hidden_dim`, `act_dim` (ints),
  - `reward_neg` (float), `format_version` (int, always 1).
- `/app/case/policy.pt` — the trained checkpoint, a file produced by
  `torch.save`. It is a **dict** with keys:
  - `"format_version"`: 1,
  - `"saved_with"`: provenance string (ignore it),
  - `"state_dict"`: the model's state dict with exactly four tensors:
    `fc1.weight`, `fc1.bias`, `fc2.weight`, `fc2.bias`.

The policy is the MLP

```
x = relu(fc1(obs))      # fc1: obs_dim -> hidden_dim
logits = fc2(x)         # fc2: hidden_dim -> act_dim
```

There is no output activation; the predicted action for a trial is the
`argmax` over the `act_dim` logits (ties resolve to the lowest index, which is
what `torch.argmax` does).

## The exact replay protocol (implement it precisely)

`python3 /app/evaluate.py <case_dir> <output_json>` must:

1. Load `env_config.json` and `policy.pt` from `<case_dir>` (open the
   checkpoint with `torch.load(..., map_location="cpu")` and take the
   `"state_dict"` entry).
2. Build the model exactly as above with a fresh `torch.nn` module and load
   the state dict **strictly** (all four tensors must match). Put the model in
   `eval()` mode and run every forward pass under `torch.no_grad()`.
3. Create the seeded environment stream — the order matters and the dtypes
   matter:
   - `rng = numpy.random.default_rng(seed)` using the config's `seed`;
   - `obs = rng.standard_normal((n_trials, obs_dim)).astype(numpy.float32)`;
   - `correct = rng.integers(0, act_dim, size=n_trials)` — the "correct"
     action per trial, drawn **after** the observations from the same `rng`.
4. Run the policy over `obs` (as one batched float32 tensor), take `argmax`
   over dim 1, and compare with `correct`.
5. Score each trial: reward `1.0` if the predicted action equals the correct
   action, otherwise `reward_neg` from the config.
6. Write `<output_json>` as valid JSON with **exactly** these keys:
   ```json
   {
     "case_id": "<string>",
     "seed": <int>,
     "n_trials": <int>,
     "n_correct": <int>,
     "mean_reward": <float>
   }
   ```
   where `n_correct` is the number of trials where prediction matched, and
   `mean_reward` is the arithmetic mean of the per-trial rewards as a Python
   float (e.g. `0.6975`).

## Deliverables

1. `/app/evaluate.py` — the program, with the CLI shown above. It must work on
   **any** case directory whose files follow this format (the grader runs it,
   unchanged, on hidden cases with different seeds, dimensions, trial counts,
   `reward_neg` values and checkpoints), not just the shipped one.
2. `/app/eval_report.json` — the report produced by
   ```
   python3 /app/evaluate.py /app/case /app/eval_report.json
   ```

## Rules and edge cases

- Do **not** modify anything under `/app/case/`.
- Never read or touch anything under `/tests` or `/solution`; they are not
  part of your task.
- The replay must be **fully deterministic**: running your program twice on
  the same case must produce byte-identical JSON. No per-run reseeding
  whimsy, no time-based values, no threading nondeterminism.
- Do not fall back to CPU-blas nondeterminism worries — this workload is
  small, single-threaded and exact; the grader's independent reference
  implementation agrees with a correct program to well within `1e-9` on
  `mean_reward` and exactly on `n_correct`.
- The grader will also verify that a *sloppy* replay fails: if you skip the
  `float32` cast, draw `correct` before `obs`, seed a different generator, or
  evaluate the wrong tensors, your numbers will not match the reference.
- No network access. `torch`, `numpy` and the Python 3.12 standard library
  are available.

## What the grader does

1. Runs `/app/evaluate.py` on the visible case and on several hidden case
   directories (each with its own `env_config.json` and `policy.pt`).
2. Compares your JSON against an independent reference implementation of the
   protocol above (exact match on `case_id`/`seed`/`n_trials`/`n_correct`,
   `mean_reward` within `1e-9`).
3. Re-runs your program and requires byte-identical output (determinism).
4. Checks `/app/eval_report.json` matches the visible reference too.
