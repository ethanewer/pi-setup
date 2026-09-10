# conduit-quill: retrieval-augmented generation over a local corpus

You are handed a local, offline knowledge base and asked to build a complete
retrieval-augmented generation (RAG) pipeline over it. There is **no network**
and **no external model** — the corpus is what you have, and everything
semantic must be computed from the local documents yourself. Your job is to
write one Python program, `/app/rag.py`, that builds a retrieval index over
the corpus and answers queries with a citation-checked summary. The verifier
runs your program against **unseen query sets** and checks four quality gates
(listed below): a declared **mean recall@5**, a **cross-wording document hit
rate**, a **citation precision**, and a minimum citation count.

## Environment

- A local corpus is at `/app/corpus.json`. It is a JSON array of documents,
  each `{"doc_id": "...", "title": "...", "body": "..."}` (400 documents; ids
  look like `doc_00000`). It is an **input**: do not modify it. It was
  generated once, deterministically, when the image was built; only the JSON
  data is present, and there is no construction recipe on disk.
- A visible dev query set is at `/app/dev/queries.json`: a JSON array of
  `{"query_id", "query", "relevant_doc_ids", "narrow_doc"}`. The
  `relevant_doc_ids` list is the document-level relevance judgement for a
  query (the documents whose content actually answers it). `narrow_doc` is the
  id of the relevant document that is written with **different wording** —
  the one whose vocabulary shares nothing with the query text. Both are
  **only** for you to measure on during development. The verifier uses the
  same schema with fresh, unseen queries and their own judgements and markers,
  which you never see.
- `/app/evaluate.py` is a readiness driver you may run to measure your
  pipeline against the dev set (run it once your program exists).
- Python 3.12 and `numpy` are installed. The corpus is small enough that a
  conventional pipeline runs in well under a minute.

## What you must build (inside `/app/rag.py`)

A reusable retrieval pipeline with four real components. The interesting
design decisions (how you segment, what semantic index you build, where the
retrieval happens) are yours. A pipeline that only matches query text verbatim
will **not** clear the gates: some documents state the requested information
with different wording, and the retrieval must still find them.

1. **Chunker** — split documents into overlapping chunks (whole sentences),
   where each chunk still maps back to its parent document id.
2. **Index** — build two retrieval structures offline:
   - a **BM25** (best-match) lexical score for every chunk, and
   - a **locally computed embedding** — a distributional/semantic model of
     the corpus that you train on the local documents yourself, entirely
     offline. This is what lets the retriever relate terms that are used
     interchangeably across documents. You choose the representation and the
     training signal; nothing external is available.
   Persist the index to a directory so it can be reused across queries.
3. **Retriever** — given a query, rank chunks and return the **top-`k`
   distinct parent documents**.
4. **Answer assembler** — compose a short prose answer from the retrieved
   material, where every claim is backed by a **citation** to the document it
   came from, and where every cited span **actually appears verbatim** in the
   cited document (no invented text).

## Output contract (the part that is specified)

`/app/rag.py` must support exactly two subcommands.

### `build`

```
python3 /app/rag.py build --corpus <corpus.json> --index <index_dir>
```

Builds the chunker, the BM25 rule, and the embedding index for the given
corpus and writes the artifacts under `<index_dir>`. It is called once before
the queries. It must exit 0 on success and print a short status line.

### `query`

```
python3 /app/rag.py query --query "<text>" --top-k N \
    --corpus <corpus.json> --index <index_dir> --out <result.json>
```

Runs the pipeline for the given query and writes JSON to `<out>` with
**exactly** these keys:

```json
{
  "query": "<the query text>",
  "retrieved_docs": ["doc_00012", "doc_00034", "doc_00119"],
  "answer": "The strandtele workflow is also referred to as kerneltarvo ... [@doc_00000] ..."
}
```

- `retrieved_docs`: the top-`N` **distinct parent document ids** chosen by
  your retriever, in rank order. Each must be a real corpus id.
- `answer`: your assembled prose, a UTF-8 string.
- If `<index_dir>` already holds a valid built index, `query` should reuse it
  (not rebuild from scratch on every query). If the index is missing, `query`
  should build it for you (make `query` self-sufficient).

### Citation format (exact)

The easiest way to guarantee the citation gate is to assemble the answer from
**sentences copied verbatim** out of the retrieved documents.

- Every sentence in the answer must be immediately followed (after at most one
  space) by exactly one citation anchor of the form `[@doc_xxxxx]`, where
  `doc_xxxxx` is the id of the document that sentence came from.
- Sentences are joined with a single space. Example answer:

  ```
  The strandtele workflow is also referred to as kerneltarvo [@doc_00000] We
  record the strandtele offset alongside the ambient temperature [@doc_00001]
  ```

- The verifier takes each anchor, reads the sentence ending immediately before
  it, normalizes case and punctuation to lowercase alphanumerics, and checks
  that the normalized sentence is a substring of the normalized cited
  document body. If it is not, that citation is invalid — so do not invent
  text, and only cite a sentence that is actually in the cited document.
- Produce at least two citations per answer.

## The gates (what the verifier enforces)

The verifier builds your index with `build`, then, for the dev set and three
hidden query sets, runs `query` on every query with `--top-k 5` and checks all
of the following on **each** query set:

1. **mean recall@5 >= 0.85** — for each query, recall is
   `|relevant_doc_ids ∩ retrieved_docs| / |relevant_doc_ids|`, averaged over
   the whole set.
2. **cross-wording doc hit rate >= 0.85** — for each query, the relevant
   document marked `narrow_doc` (the one written with different wording,
   sharing no query vocabulary) must be among your top-5. This is the gate
   that rejects a purely lexical retriever.
3. **citation precision >= 0.90** — the fraction of all `[@doc_xxx]` anchors
   whose sentence is grounded in the cited document, averaged over the set.
4. **mean citations/answer >= 2** — every answer must carry at least two
   citations on average over the set.

Recall that the hidden sets are generated the same way as the dev set (same
corpus, new queries), and that the dev set itself is there for you to iterate
against: `python3 /app/evaluate.py` prints your dev recall, cross-wording hit
rate, citation precision and citations-per-answer. Your goal is a pipeline
that is genuinely good at retrieval — not one tuned to a specific file.

## Deliverable

- `/app/rag.py` — the program described above. It must exist, support both
  subcommands, read every path from its arguments (no hard-coded absolute
  fixture paths other than what is passed in), and hit all four gates on the
  unseen hidden sets.

Use any standard-library or numpy functionality you need. Do not fetch
anything from the network. Do not modify `/app/corpus.json` or
`/app/dev/queries.json`.