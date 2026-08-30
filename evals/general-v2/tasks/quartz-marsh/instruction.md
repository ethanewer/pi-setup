# Quartz Marsh — wetland sensor bag classifier init

The Quartz Marsh ecology unit classifies **bags of sensor readings** with a tiny
two-component torch model. You must write the initialization program that builds
both components **inside a parameter budget**, save the model, and report what
you built. The verifier re-runs your program on hidden configs, so nothing may
be hard-coded.

`python3` with `torch` is installed. No network access.

## Deliverables (all three required)

1. `/app/init_model.py` — a runnable Python 3 program:

   ```
   python3 /app/init_model.py [--config PATH] [--model-out PATH] [--report-out PATH]
   ```

   Defaults: `--config /app/config.json`, `--model-out /app/model_pack.pt`,
   `--report-out /app/init_report.json`.

2. `/app/model_pack.pt` — the saved state dict (`torch.save` of
   `module.state_dict()`) produced by running the program with defaults on the
   shipped `/app/config.json`.

3. `/app/init_report.json` — the report produced by the same default run.

## The model

Define a `torch.nn.Module` whose state dict contains **exactly** these four
tensors (names and roles are fixed):

```
instance_encoder.weight   shape (H, F)     # H = your chosen hidden width
instance_encoder.bias     shape (H,)
bag_classifier.weight     shape (C, H)
bag_classifier.bias       shape (C,)
```

- `instance_encoder` must be a `torch.nn.Linear(F, H)`.
- `bag_classifier` must be a `torch.nn.Linear(H, C)`.
- `F` (feature dim) and `C` (num classes) come from the config.
- `H` is **your choice**, but it must satisfy the parameter budget below.

## The parameter budget

The combined parameter count of the two components is

```
P = F*H + H  +  C*H + C
```

(the weights and biases of both Linears). The config gives `min_params` and
`max_params`; you must pick `H >= 1` such that

```
min_params <= P <= max_params
```

Every shipped and hidden config is guaranteed to admit at least one valid `H`,
but some hidden configs admit **only one** — so compute the choice from the
config (a fixed default width will fail). Use the config's `seed` with
`torch.manual_seed` before initializing so weights are reproducible.

## Report format

`init_report.json` must be valid JSON with exactly these keys:

```json
{
  "feature_dim": 64,
  "num_classes": 5,
  "hidden_dim": 40,
  "param_count": 2805,
  "min_params": 2500,
  "max_params": 12000,
  "init_ok": true,
  "within_budget": true
}
```

- `param_count` is the true combined count `P` of the saved tensors.
- `init_ok` is `true` iff both components were created, are not `None`, and
  every tensor is finite (no NaN/Inf).
- `within_budget` is `true` iff `min_params <= P <= max_params`.
- The values must be truthful: the verifier recomputes everything from the
  saved state dict and the config and rejects contradictions.

## Config schema

```json
{
  "feature_dim": 64,
  "num_classes": 5,
  "min_params": 2500,
  "max_params": 12000,
  "seed": 7
}
```

All values are integers with `feature_dim >= 1`, `num_classes >= 1`,
`1 <= min_params <= max_params`.

**Do not modify `/app/config.json`.**
