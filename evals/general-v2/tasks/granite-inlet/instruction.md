# granite-inlet — wire up a micro model-eval suite, run it, and pick the top leaderboard entry

## Context

`/app` is the payload directory of the "Granite Inlet" model-evaluation bench. A tiny
CPU-only scorer named **cd-nano** (`/app/model/cd_nano.json`) classifies a 4-way
subject category per document: each token contributes an additive weight per class
and the predicted class is `argmax` of the summed weights over the document's tokens
(ties go to the smallest class index). Your job is to **author the evaluation
wiring** around it, run the suite, persist per-task results under the canonical
layout, and report the top model on a live leaderboard.

Everything you are allowed to *use* but never to modify is:

- `/app/model/cd_nano.json` — the tiny model (`{"name": ..., "tokens": {token: [w0,w1,w2,w3]}}`).
- `/app/data/channel_docs.jsonl` — visible classification fixture (JSON Lines; each row has
  `id`, `query`, `title`, and a pre-tokenised `words` array).
- `/app/data/channel_labels.json` — gold labels for the visible fixture (`{id: 0..3}`).
- `/app/data/queries.jsonl` — visible retrieval fixture (each row: `id`, `candidates`, `relevant`).
- `/app/board/www/index.html` — the leaderboard HTML page you must fetch.
- `/app/harness/granite_eval/` — an installed, importable harness package
  (`import granite_eval` works; install is live).

## Deliverables (create all of these in `/app`)

1. **`/app/tasks.yaml`** — the multiple-choice/log-probs task configuration. It must:
   - set `task_name` (e.g. `channel_fathom`), `n_classes: 4`, and a fixed `choices` list of exactly
     four distinct labels;
   - point `model_path` at `/app/model/cd_nano.json`;
   - select columns `query_column: query`, `title_column: title`;
   - declare a per-document gold selector (`doc_to_choice:`), keyed onto the numeric label
     supplied per document id;
   - embed the **exact default prompt template** below as `prompt_template`, which the
     harness uses to render each document (it references `{title}` and `{query}`):
     ```
     Passage subject: {title}
     Lead sentence: {query}

     Which of these four categories best matches the passage?
     [A] caldera   [B] canyon   [C] delta   [D] estuary
     ```
   The template must contain the four literals `caldera`, `canyon`, `delta`, `estuary`.

2. **`/app/register_tasks.py`** — must runnable with `python3 /app/register_tasks.py`. It imports
   the installed harness package, parses `/app/tasks.yaml`, renders a sample prompt with the
   template (verifying `{title}`/`{query}` are substituted), and writes a small registry
   manifest **`/app/tasks_registry.json`** (`{task, choices, n_classes, ...}`).

3. **`/app/run_eval.sh`** — the evaluation driver, executable. It supports:
   - no arguments → runs the visible suite and writes BOTH deliverables below
     (/app/results/channel_fathom/sprint_07.json and
     /app/results/aperture_map/sprint_07.json);
   - `run_eval.sh classify <spec.yaml> <docs.jsonl> <labels.json> <out.json>` →
     evaluates a (fresh/hidden) dataset and writes `<out.json>`;
   - `run_eval.sh retrieval <spec.yaml> <queries.jsonl> <out.json>` → writes
     a retrieval result to `<out.json>`.

4. **`/app/results/<task>/<run>.json`** — per-task metric outputs. You must produce
   **exactly** these two on the visible run:
   - `/app/results/channel_fathom/sprint_07.json` (classification, **channel_fathom**)
   - `/app/results/aperture_map/sprint_07.json` (retrieval, **aperture_map**)
   Use the schemas below.

5. **`/app/leaderboard_top.txt`** — a single trimmed line containing the `org/model`
   identifier of the row with the highest **mean** across the numeric columns of the
   fetched leaderboard page (see step 4 below).

## Classification output schema (channel_fathom)

```json
{
  "task": "channel_fathom",
  "model": "cd-nano-0.3",
  "run": "sprint_07",
  "metric": "accuracy",
  "accuracy": <float 0..1>,
  "n": <int>,"scored rows
  "correct": <int>,
  "scored": [ {"id": .., "pred": <0..3>, "gold": <0..3>, "correct": true|false}, ...],
  "skipped": [ {"id": .., "reason": "invalid-label" | "label-out-of-range"}, ...]
}
```

## Retrieval schema (aperture_name)

```json
{
  "task": "aperture_map",
  "model": "cd-nano-0.3",
  "run": "sprint_07",
  "scores": [ {"query": "q00", "recall@5": 0.5, "mrr": 1.0}, ...],
  "metrics": {"recall@5": 0.1, "mrr": 0.095},
  "n": <number of queries>,
}
```
`recall@5` = per query, fraction of `relevant` doc ids present among the first 5 of
`candidates` (0 when `relevant` empty). `mrr` = reciprocal rank of the first relevant
candidate in order (0 if none found).

## Exact scoring rules you MUST honour (this is how the metric is recomputed independently)

- A document is **scored** only when `labels[id]` exists, is an integer, and `0 <= label < 4`.
  Otherwise it is **skipped** (never counted in `n` or `accuracy`), with the reason above.
- For a scored document the predicted class is `argmax_k sum_{w in words} weight[w][k]`,
  tie broken by the smallest `k`. A document whose `words` is empty/missing is predicted
  `0`.
- `accuracy = correct / n` where `correct` = number of scored docs with `pred == gold`.
- The `n`/`correct`/`pred`/`gold`/`skipped` values must be **exact**; `accuracy` exact to
  at least 1e-6.

## Step 4 — live leaderboard

The effective leaderboard page is served over HTTP. Serve `/app/board/www/` with
`python3 -m http.server` (or equivalent) and **fetch the page over HTTP at runtime**
(`http://127.0.0.1:<port>/index.html`). Parse the HTML table: the first column is the
`org/model` name; the remaining columns are numeric per-task scores. For each row compute
the **mean** of the numeric columns, then pick the **highest mean** (ties: smaller
`org/model` name wins). Write that identifier as ONE trimmed line to
`/app/leaderboard_top.txt`. (Do not supply a precomputed answer; you must actually start
a local HTTP server, fetch, and compute.)

## Edge cases your must handle

- A document whose id is absent from `labels.json`, or whose label is not an int in
  `0..3`, is **skipped**, not counted.
- Empty `words` documents are scored and predicted `0` (still counted).
- Retrieval: queries with empty `candidates` and/or empty `relevant` must not crash; they
  contribute `recall@5 = 0` and `mrr = 0`.
- The fresh hidden datasets use the same schema as the visible fixtures (same columns,
  model, 4 classes). Your tools must never require file not present for those.

## Do NOT modify

Do not delete or alter `/app/model/cd_nano.json` or the provided `/app/data/*` and
`/app/board/www/*` fixtures. Keep `/app/harness/granite_eval/*` exactly as installed.
Your deliverables must not depend on anything outside `/app`.

## Verification hints

After wiring, run `bash /app/run_eval.sh` (default visible suite) and confirm the two
result files appear, and run `python3 /app/fetch_leaderboard.py <url>` against a server to
confirm `/app/leaderboard_top.txt` is a single trimmed line. The graded contract for the
leaderboard step is the **contents of `/app/leaderboard_top.txt`**; the script's stdout is not
graded. The grader will run the same
`run_eval.sh` subcommands on fresh hidden datasets and a fresh leaderboard page, and will
independently recompute every metric from the shipped model.<path>/app/run_eval.sh</path>