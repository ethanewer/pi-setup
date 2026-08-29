# CedarCipher — a small language-data + evaluation pipeline

You are building **CedarCipher**, a tiny CPU-only data pipeline that turns a
mixed-language dataset into filtered rows, a trained tokenizer, token counts, a
language-screened corpus, an offline-servable model shard, an lm-eval-style MCQ
harness config, and a leaderboard pull. Everything you produce lives in
`/app`.

This contract is **self-contained and exact**: exact paths, exact CLI signatures,
exact output shapes and exact edge-case behaviour. A verifier re-runs **your**
scripts on its own hidden inputs, so nothing may depend on anything you did
manually — all programs must read real data and print/ write real results.

## Read-only fixtures under `/app` (do NOT modify)

* `/app/corpus.jsonl` — one JSON **object** per line:
  `{"id": <int>, "locale": <str>, "text": <str>, "label": <str>,
    "primary": <str>, "secondary": <str>}`. `locale` is one of
  `{de,en,es,fr,pt,ar}`.
* `/app/bpe_corpus.txt` — a text file of whitespace-separated tokens (one
  typically per line). ASCII.
* `/app/documents/` — a set of `*.txt` files, **mixed scripts**: some pure
  English (ASCII), others containing non-ASCII letters (Cyrillic, Greek,
  Arabic, CJK, Devanagari).
* `/app/leaderboard_source.json` — the "live online leaderboard" grid as
  `{"metric": "...", "rows": [{"model_id": "...", ...metric values...}, ...]}`.
* `/app/mcq_dataset.json` — `{"labels": [4 strings], "samples": [{"query",
  "title", "gold": 0..3}, ...]}`.

`numpy` and `pyyaml` are installed. Use only the Python 3.12 standard library
plus those two. Do **not** add heavy ML libraries (no torch/transformers/etc.).

---

## Deliverables

### 1. Bytes-locale filter — `/app/filter_locale.py` + `/app/locale.jsonl`

A CLI script:

```
python3 /app/filter_locale.py --input FILE --locale LC --columns c1,c2,c3 --output OUT
```

- Reads `FILE` as newline-delimited JSON objects.
- Keeps exactly the rows whose `"locale"` field equals `LC` (exact string
  match).
- A row whose `locale` field is **absent** is dropped (never errors).
- For each kept row emits an object whose keys are exactly the requested
  columns, in the order requested. A requested column that a row does not
  carry is emitted as the empty string `""`(never an error, never a crash).
- Writes `OUT` as one JSON object per line (no header, empty file if zero
  rows).

Produce **`/app/locale.jsonl`** by running it on `corpus.jsonl` with
`--locale es` and `--columns id,primary,secondary`.

### 2. Offline assets — `/app/offline_assets/`

The pretrained-loader ("download") must succeed **with the network effectively
off**: every artifact it looks at must already be persisted. Create the
directory `/app/offline_assets/` containing all of:

- **`/app/offline_assets/config.json`** — JSON metadata for a small
  architecture. Must at least contain a `name` string and a `layers` integer.
- **`/app/offline_assets/tokenizer.json`** — JSON describing the tokenizer you
  build in part 3/4. Must at least contain a `"merges"` array (see part 3).
- **`/app/offline_assets/model_weights.npz`** — a `numpy.savez` archive whose
  keys are 2-D float weight shards.
- **`/app/offline_assets/loader.py`** — importable module exposing:
  ```
  load_offline(assets_dir) -> {"config": dict, "tokenizer": dict,
                                "weights": dict[str, np.ndarray]}
  ```
  Semantics (a verifier checks these):
  - It requires all three artifacts (`config.json`, `tokenizer.json`,
    `model_weights.npz`) to be present at `assets_dir`. If **any** is missing
    it must **raise** (failing to load is correct — do not try to fake it).
  - When everything is present it returns the parsed config, tokenizer and
    weights with no network calls. Reading only local files satisfies this.
  - It sets the HF-style offline environment variables
    (`TRANSFORMERS_OFFLINE`, `HF_HUB_OFFLINE`) so nothing can trigger a
    network fetch.
  - Running it as a script prints a line starting with `OFFLINE_LOAD_OK`.

> The verifier copies the whole directory, deletes one artifact, and asserts
> `load_offline` raises (complete-mirror requirement). It also asserts the
> weights dict holds only 2-D arrays.

### 3. BPE trainer — `/app/cedar_tokenizer.py`, `/app/train_bpe.py` + `/app/bpe_model.json`

Implement a small deterministic byte-pair-encoding tokenizer. Put the reusable
functions in `/app/cedar_tokenizer.py`. `train_bpe.py`:

```
python3 /app/train_bpe.py --input CORPUS --cap N --output OUT
```

**Exact training algorithm** (must be followed precisely; the verifier
re-computes it independently):

1. Read `CORPUS`, split on whitespace into words. Represent each word as its
   list of characters. The initial vocabulary is every distinct character seen
   in the corpus.
2. If the initial vocabulary already has size `>= cap`, stop: emit **no merges**
   and clip the vocabulary deterministically to its `sorted()` **first `cap`**
   entries (so `vocab_size <= cap` always holds).
3. Otherwise, repeatedly:
   - Count, across every word, each adjacent character pair `(x, y)`.
   - Pick the pair with the **highest frequency; ties broken to the
     lexicographically **smallest** pair (compare tuples as strings).
   - If the best pair frequency is `< 2`, stop.
   - If merging would take `vocab_size` to `>= cap`, stop **before** merging.
   - Merge: replace that pair by its concatenation in every word (left to
     right, non-overlapping), add the new token to the vocab, record the merge
     as `[x, y]`.

Emit `OUT` as JSON:
```json
{
  "cap": <requested cap>,
  "vocab_size": <int, never above cap>,
  "merges": [["x","y"], ... ]            // in the order they were learned,
  "vocab": [sorted token strings]
}
```

Deliver **`/app/bpe_model.json`** by running it with `--cap 240` on
`/app/bpe_corpus.txt`.

**Build the offline tokenizer** `/app/offline_assets/tokenizer.json` from the
trained model: `{"type":"cedar_bpe","merges":[[x,y],...]}` (merges in the
learned order, `"merges"` must be present to satisfy part 2).
`/app/cedar_tokenizer.py` must also expose:
- `read_words(path) -> list[str]`
- `train_bpe(words, cap) -> {"merges":..., "vocab":..., "vocab_size":...}`
- `encode(text, merges) -> list[str]`
- `load_merges(tokenizer_path) -> list[(x,y)]`

`encode` applies merges **one at a time, in the same order they were learned**,
each time scanning left→right and replacing every non-overlapping occurrence of
that pair at the current token sequence; characters not involved in any merge
remain single tokens. The number of returned tokens is used as the token count.

### 4. Tokenizer counter — `/app/tokenize.py` + `/app/token_counts.json`

```
python3 /app/tokenize.py --input FILE --output OUT [--tokenizer /app/offline_assets/tokenizer.json]
```

- Loads the `tokenizer.json` merge list from the **offline asset** via
  `cedar_tokenizer.load_merges` (default path `/app/offline_assets/
  tokenizer.json`), applies `encode` to each row's `primary` and `secondary`
  columns (a missing column counts as the empty string, i.e. 0 tokens).
- Writes `OUT` as JSON:
```json
{
  "total_tokens": <int>,                     // sum over rows of both columns
  "rows": <int>,                           // number of rows processed
  "cols": ["primary", "secondary"],
  "per_col": {"primary": <int>, "secondary": <int>}
}
```

Deliver **`/app/token_counts.json`** by running it on `/app/locale.jsonl`.

### 5. English screener — `/app/detect_lang.py` + `/app/lang_flags.json`

```
python3 /app/detect_lang.py --dir DIR --output FILE
```

- Enumerates `DIR/*.txt` in sorted filename order and classifies each with the
  **deterministic rule**: a document is **English** iff every codepoint is
  `< 0x80` (pure ASCII) **and** it contains at least one `isalpha()` letter.
  Anything else is `other`.
- Writes `FILE` as JSON `{"english": [filenames sorted], "other": [filenames
  sorted]}`. An empty directory yields `{"english": [], "other": []}`.

Deliver **`/app/lang_flags.json`** for `/app/documents`.

### 6. MCQ harness — `/app/tasks.yaml`, `/app/run_mcq.py` + `/app/mcq_result.json`

`tasks.yaml` is an lm-eval-style config. It must expose, at the top level:
`task`, `runner`, `dataset` (`/app/mcq_dataset.json`), `query_column`,
`title_column`, `gold_column`, `metric`, the fixed 4-element `labels` list that
**matches** the dataset's `labels`, and a `template` containing the placeholders
`{query}`, `{title}`, and `{c0},{c1},{c2},{c3}` for the four label names.

`run_mcq.py`:
```
python3 /app/run_mcq.py [--config /app/tasks.yaml] [--output /app/mcq_result.json]
```
- Reads the config and the dataset it points at.
- For every sample, substitutes `{query}`, `{title}`, `{c0..c3}` from the
  template to build a prompt; the gold selection is `gold_index = sample["gold"]`
  with `gold_label = labels[gold_index]`.
- Writes `/app/mcq_result.json`:
```json
{
  "task": "...", "labels": [...], "metric": "...",
  "acc": 1.0, "samples_n": <int>,
  "samples": [
    {"doc": i, "query": "...", "title": "...",
     "gold_index": <int>, "gold_label": "<str>", "prompt": "<filled>" }, ...
  ]
}
```
`acc` must be `1.0` (every sample has a gold). Run it to deliver
`/app/mcq_result.json`.

### 7. Leaderboard pull — `/app/fetch_leaderboard.py` + `/app/leaderboard_top.txt`

```
python3 /app/fetch_leaderboard.py --input SOURCE --output OUT
```
- Reads `SOURCE` (`{"metric": m, "rows": [...]}`) and emits, into `OUT`, the
  `model_id` of the row with the **highest** numeric value of metric `m`;
  ties broken to the **lexicographically smallest** `model_id`. An empty
  `rows` list emits the empty string `""`.

Deliver **`/app/leaderboard_top.txt`** for `/app/leaderboard_source.json` (do
not `cat` a precomputed value — run the script on the source file).

---

## `_execution requirements_`

- All programs are executable (`chmod +x`); a verifier calls each one exactly
  with the signatures above.
- The oracle produces every output by **running** the programs, never by
  hard-coding answers.
- Keep everything self-contained under `/app` (you may create extra helper
  modules and dirs as long as the deliverables above exist with these paths).
- Do not read, write or depend on `tests/` or `solution/`. The hidden cases
  mount new data (a different locale corpus, different `mcq`/`leaderboard`
  files, a different `documents` dir, extra BPE corpora) — your programs must
  generalize, and must behave exactly as specified above on edge inputs such
  as empty datasets, missing columns/`locale` fields, an empty documents dir,
  an empty/tied leaderboard, or a BPE `cap` below the count of distinct letters.