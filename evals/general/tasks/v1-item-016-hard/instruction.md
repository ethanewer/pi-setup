# Per-category token accounting across pinned tokenizers (hard)

Produce a per-category token-accountancy report for the snapshot dataset at
`/app/data/data.jsonl`, using the two pinned tokenizers. The dataset contains duplication and
whitespace traps; the documented normalization, deduplication, and grouping rules in
`/app/data/README.md` are authoritative — read them first. The report must be reproducible:
the same inputs must give the same numbers every run.

## Do this

1. Read `/app/data/README.md` and `/app/models/model_notes.txt` first. Apply the README's
   canonical scope exactly:
   - normalize text fields (strip leading/trailing whitespace),
   - deduplicate by exact normalized `title` (keep lowest `id`),
   - keep only `lang == "en"`, sorted by ascending `id`,
   - build per-category corpora for `scientific`, `tech`, `world`, plus the total corpus
     (join rule: `"\n"`.join of `title + "\n" + body` chunks).
2. Load both tokenizers from the pinned local snapshots
   (`/app/models/qwen/tokenizer.json`, `/app/models/deepseek/tokenizer.json`) and count all
   corpora with `add_special_tokens=False` (exact integers, no rounding).
3. Also compute, per category, which tokenizer produced the FEWER tokens, and for the total
   corpus which tokenizer is more token-efficient.
4. Reproducibility check: run your counting procedure twice (same artifacts, fresh process)
   and record `reproducible: true` if every single count is identical across the two runs.

## Output

Write `/app/report/token_accountant.json`:

```json
{
  "scope": "normalize; dedup-by-title(keep lowest id); lang==en; id asc; newline-joined",
  "pins": {
    "qwen": "Qwen/Qwen2.5-0.5B -pinned-snapshot",
    "deepseek": "deepseek-ai/DeepSeek-V3 -pinned-snapshot"
  },
  "kept_rows": 20,
  "kept_by_category": {"scientific": 9, "tech": 6, "world": 5},
  "counts": {
    "scientific": {"qwen2_5": 291, "deepseek": 280, "fewest": "deepseek"},
    "tech":       {"qwen2_5": 231, "deepseek": 233, "fewest": "qwen2_5"},
    "world":      {"qwen2_5": 92,  "deepseek": 88,  "fewest": "deepseek"},
    "total":      {"qwen2_5": 615, "deepseek": 602, "fewest": "deepseek"}
  },
  "total_corpus_chars": 1595,
  "reproducible": true
}
```

The numeric values above are the authoritative expected values for this snapshot; the verifier recomputes
every one of them from the same files. Any missed normalization step (e.g. forgetting to dedup, not
stripping, mixing categories) changes integers, so the numbers must match exactly.