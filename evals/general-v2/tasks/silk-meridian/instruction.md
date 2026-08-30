# Silk-meridian: revision-pinned document embedding and retrieval

The Silk-meridian newsroom runs a local embedding model whose behaviour is
**pinned to a revision**. Retrieval requests must be answered with embeddings
computed at exactly the pinned revision — never with vectors cached from an
older revision. Your job is to build that retrieval responder and use it to
answer the shipped request.

There is **no network access**; `python3` with `numpy` is available.

## Shipped files (do not modify anything shipped)

- `/app/model/model.py` — the embedder implementation (docstring is the
  normative algorithm). Import it as `import model` after adding
  `<model_dir>` to `sys.path`.
- `/app/model/weights.npz` — projection matrix + the revision string baked
  into the weights.
- `/app/manifest.json` — the request's pin:
  ```json
  {"model_dir": "/app/model", "weights": "model/weights.npz",
   "revision": "meridian-4.2.0", "metric": "cosine"}
  ```
  `weights` is the path to the weights file — if relative, it is resolved
  against the directory containing the manifest.
- `/app/docs.json` — `{"documents": [{"id": "doc-01", "text": "..."}, ...]}`
- `/app/query.txt` — first line `k=<int>`, remaining lines are the query text
  (join them with single spaces after whitespace-collapsing each line).
- `/app/cache/doc_vectors.npz` — a cached embedding table: arrays `ids`,
  `vectors` (row i is the embedding of `ids[i]`), and `revision` (the revision
  the cache was computed at). **The cache may be stale**: it was possibly
  computed at an older revision than the manifest pins. You may use it ONLY if
  its stored revision equals the manifest revision; otherwise recompute every
  embedding from the weights at the pinned revision.

## Revision rule (normative)

- Load the weights from `manifest["weights"]` with
  `model.load_weights` / `np.load`; this also yields the weights' own revision.
- If the weights' revision differs from `manifest["revision"]`, the pin is
  inconsistent: `/app/solve.py` must **exit with a nonzero status**, print a
  diagnostic to stderr, and write no output file.
- The `revision` field of the answer must be the manifest's pinned revision.

## Deliverables (both required)

1. **`/app/solve.py`** — a reusable responder:
   ```
   python3 /app/solve.py <manifest.json> <docs.json> <query.txt> <out.json>
   ```
   It must work on any manifest/docs/query following the formats above (the
   grader runs it unchanged on hidden cases whose pinned revision, weights,
   documents and query all differ).

2. **`/app/answer.json`** — the response for the shipped visible request:
   ```
   python3 /app/solve.py /app/manifest.json /app/docs.json /app/query.txt /app/answer.json
   ```

## Response format (`out.json` / `answer.json`)

Valid JSON with exactly these keys:

```json
{
  "revision": "<manifest revision>",
  "ranking": ["<doc id>", ...],        // ALL documents, best match first
  "selected": "<doc id>",              // the document at rank k (1-based)
  "scores": {"<doc id>": <float>, ...} // cosine(query, doc) per document
}
```

- Similarity is cosine between the pinned-revision embedding of the query and
  of each document, using the shipped `model.embed_texts` / `model.load_weights`.
- `ranking` is descending by cosine similarity (strictly: order documents by
  decreasing score; the shipped algorithm is deterministic, and hidden
  documents are pairwise distinct, so no ties occur).
- `selected` is `ranking[k-1]` for the `k` from `query.txt` (1-based; `k` is
  always within range).
- `scores` maps every document id to its (unrounded) cosine score.

## Edge cases probed by the grader

- A **stale cache** (stored revision ≠ manifest revision) must not change the
  answer — recompute from the pinned weights.
- A cache whose revision **matches** the manifest may legitimately be used
  (the answer is the same either way).
- A **manifest/weights revision mismatch** must cause a nonzero exit with no
  output file (see the revision rule).
- Hidden cases ship no cache directory at all — never assume it exists.

Do not modify any shipped file.
