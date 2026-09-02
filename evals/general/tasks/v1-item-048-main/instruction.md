# Item-048 (medium) — Deterministic, revision-pinned Chinese embeddings

A search team uses `BAAI/bge-small-zh-v1.5` (a Chinese sentence-embedding
model, 512 dims, huggingface-transformers BERT) for a semantic-matching
service. They need a **deterministic, reproducible pipeline**: every run on the
same input must produce the same scores, computed against a **pinned model
revision** — never "whatever commit happens to be the tip today".

## Files in the container

- `/app/queries_sample.txt` — sample queries (one Chinese sentence per line).
- `/app/docs_sample.json` — sample documents (JSON array of Chinese strings).
- `python3`, `curl`, `sentence-transformers`, `torch` (CPU), `numpy` are
  preinstalled. Hugging Face is reachable over HTTPS (the container trusts the
  corporate CA) and the model will be downloaded on first use into
  `~/.cache/huggingface`.

## Task

### 1. Pin the revision (research + record)

Create `/app/config.json`:

```json
{
  "model_id": "BAAI/bge-small-zh-v1.5",
  "revision": "<40-hex commit sha>",
  "normalize": true
}
```

`revision` must be a **full 40-hex commit SHA-1 of that exact model repo**,
not `"main"` and not a branch/tag. Find an authoritative current commit via
the HF API, e.g.:

```bash
curl -fsSL https://huggingface.co/api/models/BAAI/bge-small-zh-v1.5
```

The `"sha"` field of the JSON is the tip commit of `main`. (You may also
`curl -I` a specific revision URL to confirm it exists, e.g.
`https://huggingface.co/BAAI/bge-small-zh-v1.5/raw/<sha>/config.json`.)
Record that commit.

### 2. Deterministic embedding pipeline

Write `/app/embed_pipe.py` with this CLI:

```
python3 /app/embed_pipe.py --queries Q.txt --docs D.json --out results.json
```

It must read `/app/config.json` and:

1. load `SentenceTransformer(model_id, revision=<sha from config>)` from
   `sentence_transformers`,
2. embed queries and documents as **L2-normalized** float vectors
   (`normalize_embeddings=True`),
3. compute the cosine-similarity matrix `S[i][j] = dot(emb_q[i], emb_d[j])`
   (dimensions queries × documents), `float` values,
4. for each query compute `top2`: the indices (0-based, into `docs`) of the two
   highest-scoring documents **in descending score order; break score ties by
   smaller document index**,
5. write `results.json`:

```json
{
  "model_id": "BAAI/bge-small-zh-v1.5",
  "revision": "<same sha as config>",
  "queries": [...],
  "docs": [...],
  "similarity": [[...]],
  "top2": [[doc_idx, doc_idx], ...]
}
```

Determinism requirements (no randomness): same input + same pinned revision
=> byte-identical `results.json` on every run. Do NOT run tiny input sets in a
mode that could reorder due to async; process the full batch in one `encode`
call.

### 3. Validate

- Run the pipeline on the bundled sample and check the output file
  structurally.
- Write a one-paragraph note `/app/notes.md` stating the revision you pinned,
  why pinning matters for reproducibility, and how you checked `top2`.

## Success criteria (verifier)

- `/app/config.json` exists (valid JSON, keys as above).
- `revision` matches `^[0-9a-f]{40}$` and is a **real commit of
  `BAAI/bge-small-zh-v1.5`** (verifier asks the HF API; skipped if unreachable).
- `/app/embed_pipe.py` exists and runs.
- On a **fresh** deterministic input pair, the verifier recomputes embeddings
  itself with the same pinned revision and requires:
  - every `results.json` value of `similarity` equals the reference cosine
    similarity within `1e-4`,
  - `top2` matches the reference ranking exactly (including tie-breaking),
  - `results.json["revision"] == config revision`.
- `/app/notes.md` exists and is non-empty.