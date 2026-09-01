# Sable Prism — wire a multiple-choice classification task into the prismval harness

You are setting up the "Sable Prism" review-triage bench. The harness package
**`prismval` is vendored but NOT installed**; you must install it, author the
task wiring (choice order + gold mapping), run the registered task, and land
the accuracy inside the required window.

## Environment

- Working directory: `/app`. Python 3.12 with `pip` is available; `setuptools`
  is pre-installed so you can install offline. No network is available.
- **Vendored harness package** (do not modify): `/app/vendor/prismval/`.
  Install it with:
  ```
  pip install --no-build-isolation -e /app/vendor/prismval
  ```
  After installing, `python3 -m prismval --help` must work.
- **Fixed fixtures** (do not modify):
  - `/app/model/lexicon.json` — the deterministic lexicon scorer. Shape:
    `{"classes": ["negative","neutral","positive"], "bias": [b0,b1,b2],
    "weights": {"token": [w_neg,w_neu,w_pos]}}`. Score of class k is
    `bias[k] + sum(weights[token][k])` over the document's tokens (lowercase,
    `[a-z0-9']+` runs). Prediction = argmax, ties broken by the FIRST class in
    model `classes` order.
  - `/app/data/reviews.jsonl` — visible dataset; each row `{"id", "text"}`.
  - `/app/data/gold.json` — visible gold labels:
    `{"codebook": {"<code>": "<class name>", ...}, "labels": {"<id>": <code>}}`.
    **The codebook is scrambled**: code `0` means `positive`, code `1` means
    `negative`, code `2` means `neutral`. The harness itself does NOT read the
    codebook — it trusts only your config's `gold_map`, so you must encode the
    convention there. All hidden datasets use the same codebook convention.

## Harness semantics (already implemented; you only wire it)

`python -m prismval --config <cfg.json> --data <docs.jsonl> --gold <gold.json> --out <out.json>`

- For each doc, the predicted class name comes from the lexicon model.
- The gold class name is `choices[ gold_map[str(label_code)] ]` — i.e.
  `gold_map` maps label codes to **indices into the config's `choices` list**.
- A doc is scored only when its label exists, is an int, `str(code)` is a key
  of `gold_map`, and the mapped value is a valid index into `choices`.
  Otherwise it is **skipped** (reason `invalid-label` or `gold-out-of-range`)
  and never counted in `n` or `accuracy`.
- `accuracy = correct / n` where correct counts scored docs with
  `pred == gold`.

## Deliverables (all three required)

1. **`/app/task_cfg.json`** — the task config. It must contain exactly these keys:
   - `"task_name": "tone_triage"`
   - `"choices"` — an ordered list containing the three class names
     `negative`, `neutral`, `positive` (distinct; order is the choice order
     of the task and must be consistent with `gold_map`)
   - `"model_path": "/app/model/lexicon.json"`
   - `"text_column": "text"`
   - `"gold_map"` — object mapping the label codes `"0"`, `"1"`, `"2"` to
     indices into `choices`, honouring the scrambled codebook above
   - `"prompt_template"` — any template containing a `{text}` placeholder
     (e.g. `"Review: {text}\nTone?"`)
2. **`/app/run_eval.sh`** — executable driver:
   - `bash /app/run_eval.sh` (no args) runs the harness on the visible data
     (`/app/data/reviews.jsonl` + `/app/data/gold.json`) using
     `/app/task_cfg.json` and writes
     `/app/results/tone_triage/baseline.json` (create the directory).
   - `bash /app/run_eval.sh eval <config> <data.jsonl> <gold.json> <out.json>`
     runs the same harness on arbitrary (fresh/hidden) inputs and writes
     `<out.json>`. It must work for any inputs following the documented
     schema — never hard-code file contents.
3. **`/app/results/tone_triage/baseline.json`** — the visible run's output,
   produced by actually running `/app/run_eval.sh`.

## Accuracy window

The grader recomputes every accuracy independently from the shipped model and
each dataset's codebook. Your wiring is correct only if the harness-reported
`accuracy` matches the recomputed value (and `n`/`correct` match). A wrong
choice order or a wrong `gold_map` drops accuracy to near chance (well below
the window), so double-check the scrambled codebook.

## Edge cases probed by hidden inputs

- Docs whose id is missing from `labels`, or whose code is not one of
  `0/1/2`, are skipped, not scored.
- Docs with empty or unknown-token texts are scored: they fall back to the
  model bias, which favours `neutral`.
- Ties in class scores resolve to the first of `negative/neutral/positive` in
  model `classes` order.

## Constraints

- No network at verify time; the harness uses the standard library only.
- Do not modify `/app/vendor/`, `/app/model/`, or `/app/data/` fixtures.
- The grader runs `/app/run_eval.sh` unchanged on hidden datasets; it must
  therefore depend only on the arguments/document contract, not on the
  visible fixture contents.
