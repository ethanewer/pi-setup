# quartz-dial — multilingual data / tokenizer / evaluation pipeline

You are building a small language-data-and-evaluation pipeline on CPU inside
`/app`. Everything must be authored by you and must run on this machine (a
single CPU container, no GPU, network available through the corporate proxy for
the asset/leaderboard fetches). Work with **literal `/app` paths only** — do
not read or modify anything under `/tests`.

## Input data (already present, read-only)

`/app/data/news_corpus.jsonl` — one JSON object per line, 80 documents. Every
object is a dictionary with these keys (all present on every row):

```json
{"doc_id": "...", "locale": "EN|ES|FR|DE", "lang": "english|spanish|french|german",
 "title": "...", "text": "...", "query": "...", "gold": 0|1|2|3}
```

- `locale` — region tag used for stage 1 filtering.
- `lang` — the document's language (ground truth, supplied so you can sanity
  check your work; your detector must not just copy this column).
- `query`, `title` — used by the multiple-choice harness (stage 6).
- `gold` — category index for the multiple-choice task; one of `0..3` mapping
  to the fixed label set `["Politics","Science","Culture","Sports"]`.

`/app/data/eval_dev.jsonl` — 30 rows with columns `doc_id,query,title,gold`
(a dev copy of the corpus used to demonstrate the harness task is registered).

`/app/data/leaderboard.html` — **offline mirror snapshot** of the current model
leaderboard (HTML table; identical to the live page). Each body row looks like:

```html
<tr><td class="model">garnet-7b</td><td class="score">68.4</td></tr>
```

`/app/data/leaderboard_url.txt` — the live URL of the leaderboard source (read
it at runtime; its content is the same table as the mirror).

`/app/harness/eval_harness.py` — a generic multi-choice logprobs harness (read
it; it interprets **your** `/app/tasks.yaml` and is the thing that "runs the
task"). Do not modify it.

## Deliverables — all of these must exist in /app when you finish

| Path | Purpose |
|------|---------|
| `/app/filter_locale.py` | stage 1 program |
| `/app/locale.jsonl` | stage 1 output |
| `/app/offline_assets/model/` | stage 2 output (model weights + tokenizer) |
| `/app/tokenize.py` | stage 3 program |
| `/app/token_counts.json` | stage 3 output |
| `/app/bpe.py` | stage 4 program (BPE trainer, reusable on new corpora) |
| `/app/bpe_model.json` | stage 4 output |
| `/app/detect_lang.py` | stage 5 program (reusable English detector) |
| `/app/lang_flags.json` | stage 5 output |
| `/app/tasks.yaml` | stage 6 task configuration |
| `/app/fetch_leaderboard.py` | stage 7 program (reusable) |
| `/app/leaderboard_top.txt` | stage 7 output |

---

## Stage 1 — locale filter (`/app/filter_locale.py`, `/app/locale.jsonl`)

CLI (exact):

```
python3 /app/filter_locale.py --input IN.jsonl --locale LOCALE \
                              --columns c1,c2,... --output OUT.jsonl
```

Contract:
- Read `IN.jsonl` one JSON object per line.
- **Skip** blank lines, lines that are not valid JSON, and lines that are not
  JSON objects (write a warning to stderr, keep going).
- **Keep** a row iff its `locale` field, compared case-insensitively after
  stripping surrounding whitespace, equals `LOCALE` (also stripped/lowercased).
- Emit each kept row with **only** the requested columns, in the exact order
  given; a requested column missing from a row is emitted as `null`.
- Always write a valid (possibly empty) output file.

Run it now to produce the deliverable:

```
python3 /app/filter_locale.py --input /app/data/news_corpus.jsonl --locale EN \
    --columns doc_id,title,text,query,gold --output /app/locale.jsonl
```

The EN subset has exactly 44 rows. Never hard-code row content; the same
program must work on any input file with the same shape.

## Stage 2 — offline model + tokenizer assets (`/app/offline_assets/model/`)

Fetch **both** a model-weights file and its tokenizer artifacts so that, once
saved under `/app/offline_assets/model/`, both of these succeed **with the
network effectively disabled** (e.g. with `HF_HUB_OFFLINE=1`,
`TRANSFORMERS_OFFLINE=1` set):

```python
from transformers import AutoTokenizer, AutoModel
tok  = AutoTokenizer.from_pretrained("/app/offline_assets/model")
model = AutoModel.from_pretrained("/app/offline_assets/model")
```

Concretely:
- Download the **`prajjwal1/bert-tiny`** checkpoint (a tiny BERT; ~18 MB) into
  `/app/offline_assets/model/` using `huggingface_hub.snapshot_download(..., 
  local_dir="/app/offline_assets/model")`. This fetches `config.json`,
  `pytorch_model.bin` and `vocab.txt` (plus other small repo files).
- That repository ships without an explicit `model_type` and without a
  `tokenizer_config.json`, so plain `Auto*` loading would not resolve. Fix the
  local copy yourself: add `"model_type": "bert"` to `/app/offline_assets/model/config.json`
  and write a minimal `/app/offline_assets/model/tokenizer_config.json` with
  `{"tokenizer_class": "BertTokenizer", "do_lower_case": true,
  "clean_up_tokenization_spaces": true}`. This is exactly the "make offline
  loading work" step.
- **Verify now:** run the two-line load above with the offline env vars set and
  confirm it loads from disk without any network request. Everything you read
  in later stages must use this local directory (never the hub).

## Stage 3 — offline tokenization (`/app/tokenize.py`, `/app/token_counts.json`)

CLI (exact):

```
python3 /app/tokenize.py --input IN.jsonl --output OUT.json \
                         --model DIR --field FIELD
```

Contract:
- Load the tokenizer **offline** from `DIR` (same method as stage 2).
- For every JSON-object row in `IN.jsonl` (skipping blank / invalid-JSON /
  non-object lines): let `text = row[FIELD]`; tokenize with
  `tokenizer.tokenize(text)` when `text` is a non-empty string, otherwise treat
  the tokens as `[]`. A row whose field is missing/null/empty still counts as
  **one document with 0 tokens**.
- Write `OUT.json`:

```json
{"total_tokens": <sum of token counts>, "documents": <# of dict rows read>,
 "unique_tokens": <# distinct token strings>, "avg_tokens_per_doc": <int(round(total/documents)), 0 if 0 docs>}
```

- Token counting is deterministic for a fixed tokenizer and input.

Run it now:

```
python3 /app/tokenize.py --input /app/locale.jsonl --output /app/token_counts.json \
    --model /app/offline_assets/model --field text
```

This is a *counting* step: your program (or a copy of it) will be asked to
process fresh inputs later.

## Stage 4 — deterministic BPE (`/app/bpe.py`, `/app/bpe_model.json`)

Author a BPE tokenizer trainer as `/app/bpe.py` that is **fully deterministic**
and reusable on any new corpus. CLI (exact):

```
python3 /app/bpe.py --input IN.jsonl --vocab-size N --text-field FIELD --output OUT.json   # JSONL mode
python3 /app/bpe.py --input IN.txt   --vocab-size N                          --output OUT.json   # raw-text mode
```

Corpus text = the concatenation of every row's `FIELD` value (joined with `\n`)
in JSONL mode, or the whole file in raw-text mode.

The deterministic merge procedure you must implement (this is the spec the
verifier re-derives independently, so follow it to the letter):
1. Initialise the token sequence as the corpus text's characters, one token
   per character; the vocabulary is the set of distinct characters.
2. Repeat while `len(vocabulary) < N`:
   a. Count every adjacent symbol pair across the token sequence.
   b. If no pair occurs, stop.
   c. Let `maxfreq` be the maximum pair count. Among all pairs with count
      == `maxfreq`, pick the one whose **first occurrence in the token
      sequence has the smallest index**; break any remaining tie by the pair's
      lexicographic order `(left, right)`.
   d. Merge **all** occurrences of that adjacent pair at once (scanning the
      sequence left-to-right; a merged pair consumes its two input positions),
      producing a new symbol equal to the concatenation of its two parts.
      Add it to the vocabulary and record the merge as `[left, right, merged]`.
3. Write `OUT.json`:

```json
{"vocab_size": <final vocab size>, "target_vocab_size": N,
 "corpus_chars": <char count of corpus text>, "num_merges": <len(merges)>,
 "merges": [[left, right, merged], ...]}
```

Edge behaviour your trainer must handle (the verifier probes these):
- empty corpus text → `vocab_size: 0`, `merges: []`, `corpus_chars: 0`;
- a bound `N` already reached by the initial character alphabet → no merges,
  `vocab_size` = number of distinct characters (e.g. `N=1` on `"abab"` gives
  `vocab_size: 2`, `merges: []`).

Run it now (target bound 400):

```
python3 /app/bpe.py --input /app/locale.jsonl --vocab-size 400 --text-field text \
    --output /app/bpe_model.json
```

Your delivered `bpe_model.json` must exactly equal what a fresh run produces,
and must equal an independent re-derivation of this documented algorithm.

## Stage 5 — English detection (`/app/detect_lang.py`, `/app/lang_flags.json`)

Author `/app/detect_lang.py` that flags English documents in a mixed-language
JSONL corpus. CLI (exact):

```
python3 /app/detect_lang.py --input IN.jsonl --output OUT.json --text-field FIELD
```

Contract:
- For every JSON-object row that has a `doc_id`, detect the language of
  `row[FIELD]` (use the `langdetect` package — installed) and record
  `true` if the document is English, `false` otherwise.
- A row whose text is missing, is not a string, has fewer than 3
  non-whitespace characters, or cannot be attributed to a language is
  **not English** (`false`).
- Write `OUT.json`: a mapping `{"<doc_id>": true|false, ...}`.

Run it now over the full mixed-language corpus:

```
python3 /app/detect_lang.py --input /app/data/news_corpus.jsonl \
    --output /app/lang_flags.json --text-field text
```

Your detector must **generalize to documents it has never seen**; it will be
run on a held-out multilingual set and must reach an overall accuracy of at
least 90%, an English recall of at least 85%, and at least 80% accuracy within
every language group.

## Stage 6 — multi-choice logprobs task config (`/app/tasks.yaml`)

Author `/app/tasks.yaml` — a single registered task, id `quartz-article-sections`,
following the lm-eval-style schema the harness (`/app/harness/eval_harness.py`)
interprets. It must:

- read the `query` and `title` columns (query_column / title_column),
- read the gold label per document from the `gold` column
  (`gold_column: gold`) as an integer index,
- expose the **fixed choice label set**
  `["Politics", "Science", "Culture", "Sports"]`,
- embed the **mandated prompt template verbatim** (this exact string, with
  real newlines, YAML double-quoted):
  ```
  Assign the document to its explicit section. Document query: {query}
  Document title: {title}

  Available sections:
  {options}

  Provide the single section label.
  ```
  The harness fills `{query}`, `{title}` and `{options}` (options = one
  `- Label` line per label). No other text may surround these placeholders.
- select the gold label **per document** via `doc_to_choice` semantics (the
  gold column index maps to `label_set[gold]`),
- declare the metric `multiple_choice_accuracy` (overall and macro/per-label
  accuracy windows).

Schema shape (top-level: exactly one task id):

```yaml
quartz-article-sections:
  query_column: query
  title_column: title
  gold_column: gold
  label_set: ["Politics", "Science", "Culture", "Sports"]
  prompt_template: "Assign the document to its explicit section. Document query: {query}\nDocument title: {title}\n\nAvailable sections:\n{options}\n\nProvide the single section label."
  metric: multiple_choice_accuracy
```

**Register it**: run the harness once against the dev data so the task is
loaded and exercised end-to-end:

```
python3 /app/harness/eval_harness.py --task /app/tasks.yaml \
    --data /app/data/eval_dev.jsonl --out /app/eval_results.jsonl
```

It must exit 0 and print a line like
`task 'quartz-article-sections' loaded (metric=multiple_choice_accuracy, labels=4 docs=30)`.

The harness will later be run against hidden query/title rows with prediction
scores; the per-document gold selection and the overall / macro / per-label
windows it computes must be exactly right.

## Stage 7 — reach the live leaderboard (`/app/fetch_leaderboard.py`, `/app/leaderboard_top.txt`)

Author `/app/fetch_leaderboard.py` that reaches the leaderboard source **at
runtime** and emits the model identifier of the **top row** (highest numeric
`mean task score`). CLI (exact):

```
python3 /app/fetch_leaderboard.py [--url-file URLFILE] [--mirror MIRROR] [--output OUT]
```

Defaults: url-file `/app/data/leaderboard_url.txt`, mirror
`/app/data/leaderboard.html`, output `/app/leaderboard_top.txt`.

Contract:
- Read the live URL from `--url-file` (if that file exists) and attempt the
  fetch with `requests` (short timeout ~6 s, handle exceptions/timeouts). If
  the live fetch fails or returns something with no parseable rows, fall back
  to reading `--mirror` (the authoritative snapshot with identical content).
- Parse the HTML table (rows of the form
  `<tr><td class="model">NAME</td><td class="score">X.X</td></tr>`), take the
  row with the largest score, and write **only** its model identifier plus a
  trailing newline to `--output`.
- Print `top model: <id>` to stdout.

Run it now with defaults:

```
python3 /app/fetch_leaderboard.py
```

The verifier parses the mirror independently and your delivered
`/app/leaderboard_top.txt` must match its top model exactly (it will also
re-run your script, including against a hidden alternate mirror with the live
URL blocked — this is the fallback path, so make sure it works without the
network).

---

## What the verifier checks (summary)

The verifier re-runs your programs (never your JSON blobs alone): it recomputes
`locale.jsonl`, the token counts, the full deterministic BPE merge list, the
English flags, the harness task loading + accuracy windows, and the top
leaderboard model. Every deliverable path above must exist and your programs
must be runnable standalone. Do not delete or rename the `/app/data` inputs or
`/app/harness` files. There is no need to touch anything outside `/app`.
