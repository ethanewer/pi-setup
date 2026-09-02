# Token counting across two tokenizers (reproducible)

You are comparing how a Qwen2.5 tokenizer and a DeepSeek tokenizer count tokens over a
**filtered** subset of a dataset. Make the counting scope fully reproducible: follow the
dataset's own documentation, use the pinned tokenizer snapshots provided, and record those
pins in your report.

## Read first (authoritative)

- `/app/data/README.md` — the dataset documentation; it defines the **counting scope**.
- `/app/models/model_notes.txt` — which tokenizer snapshots exist and how to count with them.

## Data

`/app/data/data.jsonl` is a JSON Lines snapshot (one JSON object per line) of a synthetic
corpus. Fields include `id`, `title`, `body`, `category`, `lang`, `published`.

## Steps

1. Load the dataset from `/app/data/data.jsonl`. You may use the Hugging Face `datasets`
   library (e.g.`datasets.load_dataset("json", data_files=...)`) or the standard library —
   either is fine as long as exactly the counting scope below is reproduced.
2. Filter to rows where `category == "scientific"` **and** `lang == "en"`, then sort kept
   records by ascending `id`. (Note: the dataset also has a separate `sci` category tag; do
   NOT include it.)
3. Serialize each kept record as `title + "\n" + body`, then join those chunks in `id` order
   with a single `"\n"` separator to form one corpus string.
4. Load the pinned tokenizers: Qwen2.5 from `/app/models/qwen/tokenizer.json` and DeepSeek
   from `/app/models/deepseek/tokenizer.json`, via
   `from tokenizers import Tokenizer; Tokenizer.from_file(...)`.
5. For each tokenizer, count tokens over the FULL joined corpus:
   `len(enc.encode(corpus, add_special_tokens=False).ids)`. These numbers are exact integers.

## Output

Write `/app/report/token_counts.json`:

```json
{
  "dataset": "-2026/news-sample",
  "counting_scope": "category=scientific AND lang=en; sorted by id asc; joined with newline separators",
  "filtered_rows": <int>,
  "corpus_chars": <int>,
  "revision_pins": {
    "qwen": "Qwen/Qwen2.5-0.5B (pinned snapshot)",
    "deepseek": "deepseek-ai/DeepSeek-V3 (pinned snapshot)"
  },
  "qwen2_5_tokens": <int>,
  "deepseek_tokens": <int>,
  "larger_tokenizer": "qwen2_5"
}
```

`larger_tokenizer` is `"qwen2_5"` if Qwen counted more tokens than DeepSeek, else `"deepseek"`.
The verifier recomputes the same integer counts from the same snapshot files, so the scope and
serialization must match `/app/data/README.md` exactly.