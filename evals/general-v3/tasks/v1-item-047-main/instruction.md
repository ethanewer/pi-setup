# Item-047 (medium) — MTEB leaderboard research with documented evidence

Do real web research to answer a precise factual question about a published
embedding model, then write a machine-readable report that records exactly
**what** you looked at, **how** you filtered it, and **when** you checked it.

## Question

Find the official Chinese segment (`C-MTEB`) benchmark table published for
`BAAI/bge-small-zh-v1.5` and report:

1. the **model id** exactly as published (with the `BAAI/` namespace),
2. the C-MTEB **Average** score and the **STS** (semantic textual similarity
   task) score for that model,
3. the model's **rank** on the C-MTEB leaderboard table when all published
   models are sorted by the Average column in descending order, and the
   **total** number of models in that table,
4. the **evidence date** (the UTC date `YYYY-MM-DD` on which you personally
   observed the source),
5. the exact **source URL** you fetched the data from.

## Authoritative source

The canonical, authoritative record is the official Hugging Face model card
for `BAAI/bge-small-zh-v1.5` (maintained by BAAI, the model's publisher). The
card embeds a `### C-MTEB` section containing a markdown table whose data rows
look like:

```
| [**BAAI/bge-small-zh-v1.5**](https://huggingface.co/BAAI/bge-small-zh-v1.5) | 512 | 57.82 | 61.77 | 49.11 | ... |
```

Columns are `Model | Embedding dimension | Avg | Retrieval | STS | ...`.
Use `curl` (available in the container) to fetch the raw markdown, e.g.

```bash
curl -fsSL https://huggingface.co/BAAI/bge-small-zh-v1.5/raw/main/README.md \
  -o /app/evidence/README.md
```

Research first: confirm the correct namespace/model id and that the page you
fetch is the publisher's official card (not a mirror or a re-post). Do NOT
trust secondary sources (blogs, papers, chat summaries) for the numeric cells.

## Deliverable: `/app/report/report.json`

A JSON object with **exactly** these keys:

```json
{
  "model_id": "BAAI/bge-small-zh-v1.5",
  "benchmark": "C-MTEB",
  "column_input": "Avg",
  "value_avg": 57.82,
  "value_sts": 49.11,
  "rank": 8,
  "total": 15,
  "evidence_date": "2026-07-30",
  "source_url": "https://huggingface.co/BAAI/bge-small-zh-v1.5/raw/main/README.md"
}
```

(Numbers above are illustrative — compute them from the page you fetch; the
table currently lists 15 models and this model sits 8th on the Average
column, but always re-derive it from the live source.)

Rules:

- `model_id` must exactly equal the publisher's canonical id `BAAI/bge-small-zh-v1.5`.
- `value_avg` and `value_sts` are floats matching the C-MTEB table cells for
  THAT model (the verifier re-fetches the source and parses the table).
- `rank` = 1 + (number of models in the C-MTEB table whose `Avg` is strictly
  greater than this model's `Avg`); `total` = number of model rows in that
  table.
- `evidence_date` = the UTC date you observed the page (ISO `YYYY-MM-DD`,
  no time).
- `source_url` = the URL you actually fetched. Either the exact raw-markdown
  URL above or the plain model-card page URL
  `https://huggingface.co/BAAI/bge-small-zh-v1.5` (the verifier normalizes
  both).

## Deliverable: evidence snapshot

Save a **copy of the exact source you read** at
`/app/evidence/README.md` (create the directory). It must be a real fetch of
the raw markdown (not hand-typed): the verifier checks that the snapshot
actually contains the `C-MTEB` table and this model's row values.

## Success criteria

The verifier re-fetches `source_url` (falling back to the snapshot if the
network is down), parses the C-MTEB table, and requires:

- required keys exist with correct JSON types,
- `model_id` matches the canonical id,
- `value_avg` matches the parsed `Avg` cell (±0.01),
- `value_sts` matches the parsed `STS` cell (±0.01),
- `rank`/`total` match the parsed table counts,
- `evidence_date` is within ±3 days of the verifier's current UTC date,
- `/app/evidence/README.md` exists, contains `bge-small-zh-v1.5` and the
  `C-MTEB` section with the reported STS number.

Do not modify anything else in the container.