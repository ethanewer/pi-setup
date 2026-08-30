# ember-quarry — seismic-sensor bag classifier forward pass

Helix Geophysics is prototyping a **multiple-instance-learning (MIL)** scorer:
each sensor station contributes one *bag* of instance feature vectors (one per
acquisition window), an attention mechanism pools the bag into a single vector,
and a linear head produces one logit per event class. You must implement the
forward pass as a reusable program, `/app/mil.py`, and run it once on the
shipped station data to produce `/app/report.json`.

The grader re-runs `/app/mil.py` on **hidden stations** (different bag sizes,
feature widths, class counts, seeds — including an **empty bag** and a
**single-instance bag**), so nothing may be hard-coded to the visible fixture.

## Shipped assets (already in the image, read-only)

- `/app/config.json` — the visible station's geometry:
  `{"in_dim": ..., "hidden": ..., "num_classes": ..., "seed": ...}`
- `/app/input/bag.npz` — a numpy `.npz` archive with key `"X"`, a float32 array
  of shape `(T, in_dim)` holding one bag of `T` instance feature rows
  (`T` may be any value `>= 0`).

## Deliverables

1. `/app/mil.py` — a runnable Python program (torch available in the image):
   ```
   python3 /app/mil.py --config <config.json> --bag <bag.npz> --out <out.json>
   ```
2. `/app/report.json` — the report produced by running your program on the
   visible fixture:
   ```
   python3 /app/mil.py --config /app/config.json --bag /app/input/bag.npz --out /app/report.json
   ```

## Model contract (must be followed exactly)

`/app/mil.py` must define a `torch.nn.Module` subclass named `MILClassifier`
with constructor `MILClassifier(in_dim, hidden, num_classes)` that creates,
**in this exact order**, exactly these three layers:

- `self.encoder = torch.nn.Linear(in_dim, hidden)`
- `self.gate = torch.nn.Linear(hidden, 1)`
- `self.classifier = torch.nn.Linear(hidden, num_classes)`

It must provide these methods:

- `embed(self, x)` — `torch.relu(self.encoder(x))`, shape `(T, hidden)`.
- `attention(self, x)` — per-instance attention weights:
  `torch.softmax(self.gate(self.embed(x)), dim=0)`, shape `(T, 1)`.
  For an empty bag (`T == 0`) it must return an **empty** `(0, 1)` tensor
  instead of calling softmax (softmax over zero elements is undefined).
- `forward(self, x)` — returns a tuple `(logits, attention)` where
  - `attention` is the `(T, 1)` tensor from `attention` (empty `(0, 1)` when
    `T == 0`), and
  - `logits` is the `(num_classes,)` bag classifier output
    `self.classifier((self.embed(x) * attention).sum(dim=0))`;
    for `T == 0` return `torch.zeros(num_classes)`.

All computation on CPU, default dtype (float32). No dropout, no extra layers,
no softmax on the logits.

## CLI contract

`python3 /app/mil.py --config <config.json> --bag <bag.npz> --out <out.json>`
must:

1. Load the config JSON (`in_dim`, `hidden`, `num_classes`, `seed`).
2. Execute `torch.manual_seed(seed)` **immediately before** constructing
   `MILClassifier(in_dim, hidden, num_classes)` (no other RNG consumption
   before or between the three layer constructions).
3. Load the bag: `X` from the `.npz`, converted to a float32 tensor of shape
   `(T, in_dim)`.
4. Run `forward` and write a JSON file to `--out` with exactly these keys:
   ```json
   {
     "logits": [<num_classes> floats],
     "attention": [<T floats>],
     "instance_count": <T int>,
     "pred_class": <int>
   }
   ```
   - `attention` is the flattened list of the `T` scalar attention weights.
   - `pred_class` = `argmax(logits)` as a plain Python `int` (for `T == 0`,
     `argmax` of the all-zero logits, i.e. `0`).
5. Exit 0.

The program must work for **any** config/bag conforming to this contract,
including `T == 0` (empty `.npz` array) and `T == 1`.

## Edge cases probed by the grader

- **Empty bag** (`T == 0`): `logits` all zeros, `attention` `[]`,
  `pred_class` `0` — must not crash.
- **Single-instance bag** (`T == 1`): the single attention weight must be
  exactly `1.0` (softmax over one element).
- **Large bags** (hundreds of instances) and non-square geometry.
- Attention weights must sum to `1` (within `1e-4`) for every `T >= 1`.
- `pred_class` must equal `argmax` of the reported logits.

## Constraints

- Deterministic: same inputs → same outputs (the seed is the only randomness).
- No network access; torch and numpy are preinstalled.
- Do not modify `/app/config.json` or anything under `/app/input/`.
- Never read `/tests` or `/solution`.
