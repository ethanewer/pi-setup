# Build dialect embeddings that solve clan analogies

The **Halcyon Tidal Observatory** studies invented tide-pool "clan dialects".
Each clan has an `elder` word and a `calf` word, and analogies hold across
clans: *"the elder of clan X is to the calf of clan X, as the elder of clan Y
is to the calf of clan Y"*. You must build a reusable embedding builder that
maps every word of any such vocabulary to a vector so that **vector arithmetic
solves these analogies** and **same-clan words are semantically similar**.

You work in `/app`. The read-only fixture `/app/relations.json` is already on
disk. **Do not modify or delete any file under `/app` that you did not create
yourself, and never read or touch anything under `/tests` or `/solution`.**
The deliverables are re-checked on **hidden** relation files (different
vocabularies, clan counts, and dimensions), so nothing may be hard-coded to the
visible data.

## Deliverables (both required)

1. `/app/build_embeddings.py` — a runnable, **generic** Python program:

   ```
   python3 /app/build_embeddings.py <relations.json> <output.npy>
   ```

   It reads a relations JSON (schema below) and writes the embedding matrix to
   `<output.npy>`. It must work on **any** relations file conforming to the
   schema, use only the Python standard library plus `numpy`, and be fully
   deterministic (same input -> same output matrix).

2. `/app/embeddings.npy` — the embedding matrix your builder produces **for the
   visible fixture**:

   ```
   python3 /app/build_embeddings.py /app/relations.json /app/embeddings.npy
   ```

## Relations schema

```json
{
  "words": ["w1", "w2", ...],            // every word exactly once
  "categories": [{"name": "...", "elder": "...", "calf": "..."}, ...],
  "quadruples": [{"a": "...", "b": "...", "c": "...", "d": "..."}, ...],
  "dim": 40
}
```

- Every `elder`/`calf` in `categories` appears in `words`.
- Row `i` of your matrix must be the vector for `words[i]`.

## Required properties (checked by the grader)

The output must be a 2-D **float32** array of shape `(len(words), dim)`.

1. **Analogy.** Write `v(w)` for the row of word `w`. A quadruple
   `{a, b, c, d}` means **"a is to b as c is to d"**. The arithmetic query

   ```
   q = v(b) - v(a) + v(c)
   ```

   must rank `v(d)` **first** by cosine similarity over the whole vocabulary,
   excluding the query words `a`, `b`, `c` themselves. This must hold for
   **every** elder->calf analogy across any two **distinct** clans of the
   vocabulary — including quadruples never listed in the file (the grader
   tests fresh cross-clan combinations), and quadruples written in **either
   orientation** (elder->calf or calf->elder).

2. **Similarity.** For every clan, the cosine similarity between its `elder`
   and `calf` vectors must be **strictly positive** and **strictly greater**
   than the cosine similarity between any two words of *different* clans.

A construction that satisfies both: give every clan its own orthogonal
"clan" direction, share one fixed elder->calf shift direction across all
clans, and set `v(calf) = v(elder) + shift`. Then
`v(b) - v(a) + v(c)` equals `v(d)` exactly for cross-clan quadruples in the
elder->calf orientation (and analogously in the reversed orientation), while
same-clan words share their clan direction. You can build orthogonal
directions with `numpy` (e.g. columns of the `Q` factor from `np.linalg.qr`
on a fixed-seed random matrix). Magnitudes are free; only the relationship
properties above are judged.

## Edge cases the grader probes

- Hidden relation files with **different clan counts** (e.g. 4–8 clans) and
  **different `dim`** values; your builder must read `dim` from the file.
- Quadruples over **every pair of distinct clans**, in **both orientations**
  (`a` elder / `b` calf, or `a` calf / `b` elder).
- Word lists in **arbitrary order** — row alignment must follow `words`.
- The builder must not raise on any schema-conforming input and must always
  produce a `float32` matrix.

## Constraints

- The verifier runs `/app/build_embeddings.py` **unchanged** on hidden
  relations files, so do not special-case the visible fixture's names, sizes,
  or `dim`.
- Deterministic output; fixed seed(s) only. No network access.
- Do not modify `/app/relations.json`.
