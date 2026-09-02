# Dataset snapshot: `q-sample-v2` (hard counting scope)

JSON Lines snapshot at `data.jsonl`. Fields: `id`, `title`, `body`, `category` (one of
`scientific`, `tech`, `world` or others), `lang` (`en`, `de`, `ja`), `published`.

## Canonical counting scope (authoritative — follow exactly)

1. Load the full file.
2. **Normalize text fields**: strip leading/trailing whitespace from `title` and `body`.
3. **Deduplicate** records by exact (normalized) `title`; keep the record with the LOWEST
   `id` for each title. (Some titles appear twice on purpose.)
4. Keep only records with `lang == "en"`, and keep them sorted by ascending `id`.
5. For each kept record: chunk = `title + "\n" + body` (both normalized).
6. **Per-category** corpus: `"\n"`.join(chunks) of all kept records whose `category` equals
   that category. **Total** corpus: `"\n"`.join(chunks) of all kept records.
7. Token counts use `len(enc.encode(corpus, add_special_tokens=False).ids)`.

Rounding: none — all counts are exact integers.

## Files

- `data.jsonl` — the dataset.
- `README.md` — this file (dataset documentation).