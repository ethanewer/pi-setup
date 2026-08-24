# Item-048 (hard) — Chinese semantic retrieval with bge-small-zh-v1.5

You are building a reliability-critical **Chinese semantic document retrieval**
component for an urban search product. The embedding model is
`BAAI/bge-small-zh-v1.5`, and project rules require you to **pin the exact
revision** of the artifact you use and to produce **deterministic,
reproducible rankings** from the same snapshot.

## Data model already in the container

- `/app/model_cache/` — an offline snapshot of the `BAAI/bge-small-zh-v1.5`
  checkpoint (config, tokenizer, `model.safetensors`, pooling config,
  sentence-transformers `modules.json`). Load it from this absolute path; do
  **not** download anything.
- `/app/MODEL_SHA.txt` — records the pinned revision SHA of the bundled snapshot
  as a line of the form `sha=<hex>`. Use exactly this value.
- `/app/data/docs.txt` — the index corpus, **UTF-8**, one document per line. A
  document's id is its 1-based line number.
- `/app/data/queries.txt` — the query set, **UTF-8**, one query per line. A
  query's id is its 1-based line number.
- `/app/data/ground_truth.json` — object mapping each query id (string key) to
  the id of the document considered relevant to that query.

## What to build — `/app/retrieve.py`

Write a Python script `/app/retrieve.py` that:

1. **Pins the revision.** Read the value from `/app/MODEL_SHA.txt` and use it as
   the pinned revision. Verify the snapshot actually corresponds to that pinned
   revision (the script must derive a comparable sha from the loaded checkpoint
   or otherwise assert the pinned value). If the pinned SHA cannot be confirmed,
   exit non-zero and write `PIN_MISMATCH` to `/app/error.txt`. The correct pinned
   value for this bundle is exactly what `/app/MODEL_SHA.txt` contains.

2. **Embeds with SentenceTransformers.** Build a `SentenceTransformer` directly
   from the local path `/app/model_cache`. Embed each **query** with the bge
   query-instruction prefix `为这个句子生成表示以用于检索相关文章：`; embed each
   **document** with **no** prefix. Encode with `normalize_embeddings=True` and a
   modest `batch_size` (e.g. 16). Let the cosine similarity between query `q` and
   document `d` equal the dot product of their two normalized embeddings.

3. **Ranks deterministically.** For each query, sort corpus documents by
   descending similarity; **break ties by ascending document id**. Then
   `rank_of_relevant` = 1-based position of the ground-truth relevant document in
   this sorted order, and `top_doc_id` = the id of the highest-ranked doc.

4. **Preserves indexing and line order.** Exactly one output line per query, and
   the output order must be exactly query id 1, 2, ..., N. Never drop, reorder,
   or duplicate query lines, and never renumber documents.

## Deliverable — `/app/ranks.jsonl`

UTF-8, newline-delimited JSON, one object per query in input order:

```json
{"query_id": 1, "relevant_doc_id": 11, "rank_of_relevant": 3, "top_doc_id": 7, "pinned_sha": "sha=<full hex from MODEL_SHA.txt>"}
```

`pinned_sha` must be exactly the `sha=` value read from `/app/MODEL_SHA.txt`.
Nothing else printed to this file.

## Success criteria (verifier recomputation)

The verifier independently embeds the same data with the same model and procedure
and asserts, for every query:
- output has exactly one line, in query-id order 1..N (no drop/reorder);
- `rank_of_relevant` and `top_doc_id` equal the verifier's own values;
- `pinned_sha` equals the value in `/app/MODEL_SHA.txt`;
- running your script twice yields byte-identical output.

Required libraries (sentence-transformers, torch, transformers, tokenizers) are
already installed. You may `pip install` more if you like. Do **not** modify
anything under `/app/data/`, `/app/MODEL_SHA.txt`, or `/app/model_cache/`.

Hint: run `/app/retrieve.py`, then run it again and compare outputs; iterate
until 5 valid JSON lines appear with the expected fields and repeated runs are
byte-identical.