# Add a classification task to the fen_eval harness and match the accuracy window

`/app` is the payload of the **Fen Lantern wetland bioacoustics bench**. A tiny
deterministic scorer, **fen-scout** (`/app/model/fen_scout.json`), assigns each
field-recording note to one of four wetland species. The harness package
`fen_eval` is already installed and importable (`import fen_eval` works; its
source lives at `/app/harness/fen_eval/`). Your job is to **author the task
wiring**: define the multiple-choice task, drive it through the installed
harness package, and land the reported accuracy inside the required window.

Everything you may *use* but never modify:

- `/app/model/fen_scout.json` — the model: `{"name", "classes", "vocab"}` where
  `classes` is the ordered class-name list (internal class `k` is `classes[k]`)
  and `vocab` maps a token to one additive weight per class.
- `/app/data/wetland_docs.jsonl` — visible fixture; one JSON object per line
  with `id`, `note`, and a pre-tokenised `tokens` array (some docs omit it).
- `/app/data/wetland_labels.json` — gold labels for the visible fixture, as
  **species-name strings** (e.g. `"crake"`), keyed by doc id.
- `/app/harness/fen_eval/` — the installed harness package (do not edit).

## Scoring contract (fixed by the harness — recompute-able)

- The score of class `k` for a doc is the sum of `vocab[tok][k]` over the doc's
  `tokens` (tokens absent from the vocab contribute 0).
- The predicted **choice index** is the argmax over classes, ties broken by the
  **lowest** index. A doc with an empty or missing `tokens` list is predicted
  index `0`.
- The `choices` list in the task config fixes what each index means: choice `i`
  corresponds to internal class `i`. **The choices list must therefore list the
  four class names in exactly the model's internal `classes` order.**
- Gold labels are species-name strings; the config's `doc_to_choice` table maps
  each gold label string onto its index in `choices`. A doc whose id is absent
  from the labels file, or whose label string is not a key of `doc_to_choice`,
  is **skipped** (reason `unmapped-label`) and never counted in `n`.

## Deliverables (create all three)

1. **`/app/tasks/wetland_calls.yaml`** — the task configuration. It must set:
   - `task_name: wetland_calls` and `run_name: baseline`;
   - `model_path: /app/model/fen_scout.json`;
   - `choices:` the four species names **in the model's internal `classes`
     order**;
   - `doc_to_choice:` the mapping from each gold label string to its index in
     `choices`;
   - `prompt_template:` the **exact** template below (it must contain the
     `{note}` placeholder and all four species literals):
     ```
     Field note: {note}

     Which wetland species made this call?
     [0] bittern   [1] crake   [2] grebe   [3] warbler
     ```

2. **`/app/run_task.py`** — runnable as
   `python3 /app/run_task.py <task_yaml> <docs_jsonl> <labels_json> <out_json>`.
   It must `import fen_eval` (the installed package) and use it to load the
   spec and model, render at least one sample prompt via the harness's
   `render_prompt` (verifying `{note}` substitutes), evaluate the docs against
   the labels, and write the harness's result object as JSON to `<out_json>`.
   It must work on **any** docs/labels pair with the same schema, not just the
   visible fixtures.

3. **`/app/results/wetland_calls/baseline.json`** — the result your runner
   produces on the visible fixture:
   ```
   python3 /app/run_task.py /app/tasks/wetland_calls.yaml \
       /app/data/wetland_docs.jsonl /app/data/wetland_labels.json \
       /app/results/wetland_calls/baseline.json
   ```

## Result schema (produced by `fen_eval.evaluate`)

```json
{
  "task": "wetland_calls",
  "model": "fen-scout-0.4",
  "run": "baseline",
  "metric": "accuracy",
  "accuracy": <float 0..1>,
  "n": <int>,
  "correct": <int>,
  "scored": [ {"id": "..", "pred": <0..3>, "gold": <0..3>, "correct": true|false}, ... ],
  "skipped": [ {"id": "..", "reason": "unmapped-label"}, ... ]
}
```

## Accuracy window

Every evaluation produced by `/app/run_task.py` — on the visible fixture and on
any hidden re-run — must report `accuracy` inside the window **[0.55, 1.00]**.
A mis-ordered `choices` list or an inconsistent `doc_to_choice` mapping does
not crash anything: it silently skews `pred`/`gold` alignment and drives
accuracy far below the window. The verifier recomputes every number
(`n`, `correct`, `accuracy`, per-doc `pred`/`gold`, `skipped`) independently
from the shipped model, your config, and the data, and requires an exact match
with your runner's output.

## Hidden re-runs

The verifier re-runs `python3 /app/run_task.py /app/tasks/wetland_calls.yaml
<hidden_docs.jsonl> <hidden_labels.json> <out.json>` on fresh datasets with the
same schema. They include: docs with empty or missing `tokens` (predicted
index 0), docs whose id is missing from the labels file, and docs whose label
string is not one of the four species (skipped as `unmapped-label`). Your
runner must not crash on any of these.

## Do NOT modify

`/app/model/fen_scout.json`, `/app/data/*`, and `/app/harness/fen_eval/*` are
read-only inputs. No network access is needed or available at verify time;
standard library plus the installed `fen_eval` and `pyyaml` suffice.
