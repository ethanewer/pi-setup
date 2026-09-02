# opal-fathom — deterministic seeded rollout of a trained routing policy

Your team ships a small trained **signal-routing policy** to an edge device.
Before release, the policy must pass a **deterministic evaluation gate**: the
same seed must produce byte-stable rollout metrics every time the evaluation
is re-run, and the reported mean reward must match what the policy actually
achieves in the documented environment.

You must write ONE program, `/app/eval_policy.py`, that loads the policy and
runs the documented fixed-seed reward-collection loop, then run it yourself to
produce the release report.

## Provided fixture (read-only)

`/app/case/` contains:

- `env_config.json` — evaluation configuration:
  `case_id`, `seed`, `n_states` (S), `n_actions` (A), `horizon` (T),
  `episodes` (E), `obs_dim`, `hidden_dim`, `transition`,
  `policy_file` (`"policy.npz"`), and `min_mean_reward`.
- `policy.npz` — the trained policy, a NumPy `.npz` archive with exactly four
  arrays (float32):
  - `W1` shape `(hidden_dim, obs_dim)`, `b1` shape `(hidden_dim,)`
  - `W2` shape `(n_actions, hidden_dim)`, `b2` shape `(n_actions,)`

**Do not modify anything under `/app/case/`.**

## The policy (consumed exactly as specified)

For a state `s` (integer `0 <= s < S`), build the observation as a float64
one-hot vector `obs` of length `S` with `obs[s] = 1.0`, then:

```
h      = tanh(W1 @ obs + b1)        # float64
logits = W2 @ h + b2                # float64
action = argmax(logits)             # int; on ties take the LOWEST action index
```

(The cast of the float32 stored arrays to float64 must happen before the
matrix products.)

## The environment (deterministic; replicate this recipe exactly)

All randomness comes from one seeded generator, consumed in exactly this
order — the reward table first, then the episode start states:

```python
rng = numpy.random.default_rng(seed)                       # seed = cfg["seed"]
R      = rng.integers(0, 4, size=(S, A)).astype(numpy.float64) / 3.0
starts = rng.integers(0, S, size=E)                        # E start states
```

Each episode `e` (for `e = 0 .. E-1`) runs `T` steps:

```python
s = int(starts[e]); total = 0.0
for t in range(T):
    action = policy_action(s)          # the argmax rule above
    total += R[s, action]              # per-step reward
    s = (s + action + 1) % S           # deterministic transition
```

There is no other source of randomness: with the same seed, the whole loop is
fully determined. `mean_reward = (sum of all episode totals) / (E * T)`.

## Deliverable 1 — `/app/eval_policy.py`

A runnable program with this interface (both arguments optional with these
defaults, so the verifier may point it at other case directories):

```
python3 /app/eval_policy.py [case_dir] [output_json]
# defaults: case_dir=/app/case  output_json=/app/eval_report.json
```

It must:

- read `env_config.json` and `policy.npz` from the case directory (use the
  `policy_file` value from the config as the archive filename — do not
  hardcode `"policy.npz"` blindly, and read all dimensions/counts from the
  config, never hardcode them);
- run the seeded reward-collection loop described above;
- write valid JSON to the output path with **exactly** these keys:
  - `"case_id"` — copied from the config,
  - `"seed"` — copied from the config,
  - `"episodes"` — E,
  - `"horizon"` — T,
  - `"mean_reward"` — the mean reward over all `E*T` steps (float),
  - `"episode_rewards"` — a list of E floats, the per-episode totals in order,
  - `"total_steps"` — E*T.

The program must be **purely deterministic**: running it twice on the same
case directory must produce identical reports. Do not use any randomness
source other than the seeded recipe above. Do not read `/tests` or `/logs`.
Standard library + `numpy` only.

## Deliverable 2 — `/app/eval_report.json`

The report produced by running your program on the provided case:

```
python3 /app/eval_policy.py /app/case /app/eval_report.json
```

## Quality gate

The policy is trained, so a correct evaluation must clear the release floor:
`mean_reward >= min_mean_reward` (from `env_config.json`). A policy that is
loaded incorrectly (wrong arrays, wrong shapes, transposed weights, random
re-initialisation) will diverge from the reference rollout and fail.

## Edge cases the verifier probes (hidden cases)

The verifier re-runs your program on fresh hidden case directories with
different `seed`, `n_states`, `n_actions`, `horizon`, `episodes` and
`hidden_dim` values and checks the same contract, including:

- start states that repeat across episodes (each episode runs independently
  from its own start state);
- reward tables containing tied best actions (the tie must resolve to the
  **lowest** action index);
- states whose greedy action is action `0`;
- cases where `n_actions == 2`.

The verifier also re-runs your program twice per case and requires the two
reports to agree exactly, and requires your reported numbers to match its own
independent implementation of the recipe above.
