# Sable Vellum — wire a classification task into the vellum_eval harness

`/app` is the payload directory of the **Sable Vellum** card-sorting bench. A
micro lm-eval harness package **`vellum_eval`** is already installed and
importable (`import vellum_eval` works). Your job is to **author the
evaluation wiring** for a 3-way classification task, run the suite over HTTP
against the visible corpus, and persist the per-task result. The verifier will
re-run YOUR driver on fresh hidden corpora, so everything must be generic.

Everything you may *use* but never modify:

- `/app/model/vex_nano.json` — the tiny scorer ("vex-nano"). Its `tokens`
  table maps a token to a 3-vector of additive class weights
  `[herb, tree, moss]`.
- `/app/corpus/docs.jsonl` — visible classification fixture (JSON Lines; each
  row has `id`, `title`, `excerpt`, and a decoy `collector` column).
- `/app/corpus/labels.json` — gold labels for the visible fixture, mapping
  doc id -> choice LABEL string (`"herb"`, `"tree"` or `"moss"`).
- `/app/harness/` — the installed `vellum_eval` package source (do not edit;
  the verifier imports the installed copy).

## Harness semantics (deterministic, fully documented)

- A document's text is `"{title}\n{excerpt}"` using the task's configured
  columns. Tokens are all `[a-z0-9]+` runs of the lowercased text.
- Score for class k = sum of `weights[token][k]` over the document's tokens;
  unknown tokens contribute nothing. Predicted class = argmax, **ties broken
  by the smallest class index**; a document with no known tokens is predicted
  class 0.
- Gold class index = the position of the label string in the task's declared
  `choices` list. **The declared choice order is therefore part of the
  contract** — a wrong order silently mislabels every document. A document
  whose label is missing or not one of the declared choice labels is
  *skipped* (reason `invalid-label`) and excluded from `n` and `accuracy`.

## Deliverables (create all three in `/app`)

1. **`/app/task_vellum.yaml`** — the task configuration. It must contain:
   - `task_name: card_sortis`;
   - `n_classes: 3`;
   - a `choices` list of exactly the three labels **in this order**:
     `herb`, `tree`, `moss` (this order defines the gold class indices);
   - `model_path: /app/model/vex_nano.json`;
   - `query_column: excerpt` and `title_column: title`;
   - `doc_to_choice: gold_label` (the documented gold selector);
   - a `prompt_template` referencing `{title}` and `{excerpt}` and containing
     the three literals `herb`, `tree`, `moss`, e.g.:
     ```
     Archive card: {title}
     Excerpt: {excerpt}

     Which of these three plant groups best matches the card?
     [0] herb   [1] tree   [2] moss
     ```

2. **`/app/run_cards.py`** — the evaluation driver, runnable as:
   ```
   python3 /app/run_cards.py <task_yaml> <docs_url> <labels_url> <out_json>
   ```
   It must **fetch both the docs (JSON Lines) and the labels (JSON) over
   HTTP** from the given URLs, score them with the installed `vellum_eval`
   package using the task config, and write the result JSON to `<out_json>`.
   Do not hard-code the visible URLs or file contents — the verifier calls
   this same script with fresh hidden URLs.

3. **`/app/results/card_sortis/visible.json`** — the result produced by
   running your driver against the **visible** corpus served over HTTP. Serve
   `/app/corpus` yourself (e.g. `python3 -m http.server 8821 --directory
   /app/corpus`) and run:
   ```
   python3 /app/run_cards.py /app/task_vellum.yaml \
       http://127.0.0.1:8821/docs.jsonl \
       http://127.0.0.1:8821/labels.json \
       /app/results/card_sortis/visible.json
   ```

## Result JSON schema

```json
{
  "task": "card_sortis",
  "n": <int>,            // number of scored (non-skipped) documents
  "correct": <int>,
  "accuracy": <float>,   // correct / n, exact to at least 1e-6
  "scored":   [ {"id": .., "pred": <0..2>, "gold": <0..2>, "correct": true|false} ],
  "skipped":  [ {"id": .., "reason": "invalid-label"} ]
}
```

`n`, `correct`, every per-document `pred`/`gold`, and the skipped set must be
**exact**; the verifier recomputes all of them independently from the model
and the corpus.

## Accuracy window

With the correct wiring (right choice order, right gold mapping) the visible
run lands at accuracy ≈ **0.88**. The graded window is **0.60–0.95**: a
permuted `choices` order or a reversed gold mapping drives accuracy far below
0.60 and fails the check. The verifier recomputes the exact expected accuracy
anyway, so do not tune numbers by hand — wire the task correctly.

## Edge cases the hidden corpora probe

- Documents absent from the labels map, or whose label is not one of the
  declared choice labels → skipped, never counted.
- Documents with an empty/missing `excerpt` → still scored (predicted 0).
- Documents with exact score ties → smallest class index wins.
- Uppercase/mixed-case text → lowercased before tokenizing.
- Decoy columns (`collector`) must be ignored.

## Constraints

- Work only under `/app`. Never read or depend on `/tests` or `/solution`.
- Do not modify `/app/model/vex_nano.json`, `/app/corpus/*`, or
  `/app/harness/*`.
- No network access beyond `127.0.0.1` loopback HTTP; standard library +
  installed packages only.
- The verifier re-runs `/app/run_cards.py` unchanged on hidden corpora served
  from a fresh port, so the script must take its URLs from argv.
