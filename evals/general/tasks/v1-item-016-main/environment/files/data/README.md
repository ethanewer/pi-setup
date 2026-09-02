# Dataset snapshot: `delta-news-sample`

Local JSON Lines snapshot (`data.jsonl`) of a synthetic multilingual news/scientific corpus.
This is the dataset "documentation" — read it before counting.

## Format

One JSON object per line. Fields:

| field | type | meaning |
|-------|------|---------|
| `id` | int | stable, unique record id |
| `title` | str | short headline |
| `body` | str | article body text |
| `category` | str | one of `scientific`, `sci`, `tech`, `world`, `general` |
| `lang` | str | `en`, `de`, or `ja` |
| `published` | str | ISO date `YYYY-MM-DD` |

## Canonical counting scope (IMPORTANT — follow exactly)

- Load the full file first.
- Apply the filter `category == "scientific"` **and** `lang == "en"`.
- Keep records sorted by ascending `id`.
- For each kept record, concatenate `title + "\n" + body` to form that record's text chunk.
- Join all kept chunks in `id` order with a single `"\n"` separator to form one corpus string.
- Tokenize that corpus string **without** adding special tokens
  (`add_special_tokens=False`). The count is the length with `encode(...).ids`.

The `scientific` + `en` filter (not `sci`) is intentional; `sci` is a different category tag.

## Reporting

Write the report to `/app/report/token_counts.json` (see task instruction for the exact schema).