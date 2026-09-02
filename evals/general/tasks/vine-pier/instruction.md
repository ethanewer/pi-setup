# Vine-pier: local small-model inference & lifecycle

You are the ML-infra engineer at **Vine-pier** Labs. The "Vertex" retrieval-and-
generation stack ships as a **bespoke serialized transformer checkpoint** plus a
**byte-pair vocabulary**, both stored locally — there is **no network access**
in this environment, so nothing may be downloaded. Your job is to author, from
scratch, the small **dependency-free** tooling that the lab runs: a pure-C
reader for the checkpoint and vocabulary, a greedy generator, a speculative
draft-and-verify loop, a revision-pinned retrieval scorer, and the persistence
of the "fitted" model (pickle + a structured params report).

Everything you must build lives at `/app`. The shipped fixtures are at:

- `/app/data/checkpoint.ckpt` — the Vertex transformer checkpoint (custom binary).
- `/app/data/vocab.txt` — the byte-pair vocabulary (tab-separated text).

**Do not modify or move anything under `/app/data`.** You may create any
supporting files in `/app`, but you MUST produce exactly the deliverables below.
`python3` with `numpy` (and the C compiler `gcc`) are available; nothing else is
needed.

---

## 1. The checkpoint format (`/app/data/checkpoint.ckpt`)

All integers are **little-endian**. Layout from byte 0:

| offset | size | meaning |
|---|---|---|
| 0 | 6 | magic ASCII `VINER1` |
| 6 | 2 | reserved (zero) |
| 8 | 4 (u32) | `vocab_size` **V** |
| 12 | 4 (u32) | `n_tensors` |
| 16 | 4 (u32) | `max_gen` — greedy generation length |
| 20 | 4 (u32) | `d_emb` — embedding dimension |
| 24 | 4 (u32) | `rev_len` |
| 28 | `rev_len` | revision name (ASCII, no spaces) |
| after | . | tensor records |

Each **tensor record**, in order:

| size | meaning |
|---|---|
| 4 (u32) | `name_len` |
| `name_len` | tensor name (ASCII, no spaces) |
| 1 (u8) | `dtype` (always `0` = float32) |
| 1 (u8) | `ndim` |
| 4·`ndim` (u32[]) | per-dimension sizes |
| 4·nelems | row-major float32 data, little-endian (`nelems` = product of dims) |

The shipped checkpoint has `vocab_size=32`, `max_gen=8`, `d_emb=8`, and exactly
four tensors named **`W`** (shape `V,V,V` — the target next-token logits),
**`D`** (shape `V,V,V` — the draft model's next-token logits), **`B`** (shape
`V`, target bias), and **`emb`** (shape `V×8`, token embeddings for retrieval).
The **verifier also runs your code against a hidden checkpoint** with a
*different* vocabulary size, revision, max_gen, and (possibly) tensor data — your
parsing must be fully generic (driven by the header, never by hard-coded
sizes).

## 2. The byte-pair vocabulary (`/app/data/vocab.txt`)

Text file, one entry per line: `id<TAB>token`, e.g. `3\tvg_003`. `id` is a
decimal integer `0..V-1`; `token` is a printable ASCII byte-pair label with **no
spaces or tabs**. There is exactly one line per id. Reading it must produce the
id→token map the checkpoint's `vocab_size` declares.

---

## 3. Deliverable A — pure-C reader `/app/ckpt_reader.c` (+ compiled `/app/ckpt_reader`)

Write **`ckpt_reader.c`** with **no dependencies beyond the C standard library**
and compile it to **`/app/ckpt_reader`**. It reads:

```
/app/ckpt_reader <checkpoint.ckpt> <vocab.txt>
```

and prints to **stdout** a deterministic report that is compared **byte-for-byte**
to a reference:

```
REV <hex>                    # the 6-byte revision of the header, lowercase hex, no spaces
VSIZE <V>
MAXGEN <mg>
CKPT <name> =0 <ndim> [<d0> ... <d_{nd-1}>] nelems=<e> fn=<16-lowercase-hex>
...
---
TOK <id> <token>
TOK <id> <token>
...
```

- One `CKPT ...` line **per tensor, in file order**. Exact fields:
  `<name>` (as stored), `dtype` is `0`, since the `<ndim>` dims in brackets,
  `nelems` (total element count), and `fn` = a **FNV-1a-64** checksum of the
  tensor's **raw stored bytes** (the little-endian float32 data, *before* any
  endian conversion). FNV-1a-64: hash = 14695981039346656037; for each byte:
  `hash ^= byte; hash *= 1099511628211; hash &= 0xFFFFFFFFFFFFFFFF`. Output the
  hash as 16 lowercase hex digits.
  - The **format string is exact** (no extra spaces):
    `CKPT <name> dtype=0 ndim=<ndim> [<d0> <d1> ...] nelems=<e> fn=<16hex>`
- After `---`, one `TOK <id> <token>` line per vocabulary entry **in ascending
  id order**, with the exact token text from the file.

The reader must exit non-zero cleanly (no crash, no garbage) if a file is
missing or malformed, but it will be run only on well-formed checkpoints from
the tests. Do not do anything clever with sizes — read them from the header.

Your **continuation**/compiled reader is also re-run by the verifier on the
shipped checkpoint **and** the hidden one; both dumps must match the reference
exactly.

---

## 4. The model semantics (shared by generated programs)

A "next-token" prediction uses the **last two tokens** of a sequence:

```
score_i = W[a, b, i] + B[i]        # target model
draft_i = D[a, b, i]              # draft model (no bias)
next = argmax_i(score)  with ties broken to the lowest index
```

`numpy.argmax` returns the **lowest** index on ties, so `int(np.argmax(...))`
gives the required deterministic result. Prompts/contexts are always at least 2
tokens long.

---

## 5. `/app/generate.py` — greedy target-sequence generation

Usage:

```
python3 /app/generate.py --model <ckpt> [--prompt 2,4] [--out FILE]
```

- `--prompt` : comma-separated integer token ids (default `2,4`).
- `--out`    : where to write the JSON (default `/app/greedy_out.json`).
- Reads W and B from the checkpoint, starts `seq = prompt`, and appends exactly
  `max_gen` greedy tokens using the target model. Writes JSON:

```json
{
  "ckpt": "<ckpt path>",
  "revision": "<rev>",
  "max_gen": 8,
  "prompt": [2,4],
  "continuation": [ ...max_gen ids... ],
  "full": [ ...prompt + continuation... ]
}
```

The verifier re-runs `generate.py` on **hidden prompts** (varying lengths ≥2,
leading tokens repeated) and compares `continuation`/`full` token-for-token to a
reference. It also already contains your visible default `greedy_out.json`.

## 6. `/app/speculative.py` — draft-and-verify loop against a target sequence

```python
python3 /app/speculative.py --model <ckpt> --prefix <a,b> --target <t1,t2,...> [--draft K] [--out FILE]
```

- `--prefix`  : comma-separated starting context (≥2 ids). Default `2,4`.
- `--target`  : the **reference continuation** (comma-separated ids) to verify
  the proposed draft against. This is the ground-truth next tokens (already
  known from a prior greedy run).
- `--draft`   : the draft block length `K` (default `3`).

Algorithm (loop until the context has absorbed the full `prefix + target`):

1. From the current context, propose a draft block of **K** tokens using the
   draft model `D` (greedy argmax over last two, no bias).
2. **Verify**: compare each proposed token to the target sequence at the same
   absolute position, prefix the accepted run **up to the first mismatch**.
3. Extend the context by those accepted tokens.
4. If the block was cut short by a mismatch, the **next token of the target** is
   the "verified" token — append it (the verified target token) and continue.
5. Repeat.

Write JSON to `--out`:

```json
{
  "ckpt": "<path>",
  "revision": "<rev>",
  "prefix": [...],
  "target": [...],
  "draft_len": K,
  "result": [ ...final context = prefix + target... ],
  "n_drafted": 0,
  "n_accepted": 0,
  "n_verified": 0,
  "blocks": [
     {"start": 2, "draft": [ ...K ids...], "accepted": 0, "rejected": true }, ...
  ]
}
```

- `n_drafted`  = total proposed draft tokens (sum of block lengths).
- `n_accepted`  = total draft tokens actually accepted into the context.
- `n_verified` = `len(target) - n_accepted`.
- `blocks`, in order, one per loop iteration: `start` = absolute position of the
  block, `draft` = the proposed block, `accepted` = length of the accepted
  prefix, `rejected` = true when the block was cut short by a mismatch (and
  there were still target tokens left).

Ties/off-by-one: a fully-accepted block still advances; a `K` that exceeds the
remaining target length must accept exactly the remaining length. The verifier
runs this on hidden prefix/target/`K` combos (including a target that is exactly
the draft model's own continuation — every block accepted — a short target, and
`K=1`) and checks `result`, `n_drafted`, `n_accepted`, and every `blocks` against
the same loop. It also already contains your visible default pass at
`/app/spec_out.json` (produced with `--prefix 1,2`, the target-model greedy
continuation of that prefix as the `--target`, and `--draft 3`).

## 7. `/app/retrieve.py` — revision-pinned retrieval + cosine ranking

```python
python3 /app/retrieve.py --model <ckpt> --docs "<d1>;<d2>;..." --query "<q1,q2>" [--out FILE]
```

- `--docs` : a list separated by `;`; each doc is a comma-separated id list.
- `--query` : comma-separated token ids.

Embedding: a sequence's vector = the **sum-of-elements** of the `emb` rows for its
token ids, then **L2-normalized**; the query ditto. Cosine to a zero/norm vector
is `0.0`. Rank documents by cosine, **descending**, ties broken by the **lower
doc index**. The **revision must be pinned** — the `emb` used must come from the
checkpoint whose `revision` is reported.

Writes JSON:

```json
{
  "ckpt": "<path>",
  "revision": "<rev>",
  "query": [...],
  "docs": [[...], ...],
  "embedding_dim": 8,
  "rank": [ {"doc": 0, "position": 1, "cosine": 0.9}, ... ],
  "selected": <doc index of rank 1>,
  "fifth": <doc index of rank 5, or null when fewer than 5 docs>
}
```

`rank` is ordered by similarity; `position` is 1-based. The verifier runs hidden
corpor/a (e.g. with duplicate docs, an **empty doc**), an **empty query**, more
than five docs) and compares `rank`, `selected`, `fifth`, `embedding_dim`, and
`revision` exactly. It also already contains your visible default pass at
`/app/ranks.json` (produced with `--docs "1,1,9;5,4;6,0;2,6,3;1,9,9"` and
`--query "2,4"`).

## 8. Persist the fitted model to pickle — `/app/model.pkl`

Build a small **`/app/report.py`** helper that reads the checkpoint and "fits"
the target's parameters into a plain dict:

```python
{"W": W, "b": B, "revision": <rev>, "fitted": True, "vocab_size": V}
```

(`W` and `b` are the float32 numpy arrays from the checkpoint) and `pickle.dump`s
it to `/app/model.pkl`. The pickle file must be **non-empty** and reloadable with
`pickle.load`. The verifier reloads it and validates the shapes/values.

## 9. Structured two-peak params report — `/app/params.json`

From the same fitted model, write `/app/params.json` with the **exact** top-level
layout:

```json
{
  "model": "vertex",
  "fitted": true,
  "vocab_size": 32,
  "revision": "<rev>",
  "peaks": {
     "W": [ [ [ ...32768 floats... ] ] ],
     "B": [ ...32 floats... ]
  }
}
```

- Top-level keys are **exactly** `model`, `fitted`, `vocab_size`, `revision`,
  `peaks`.
- `peaks` holds **exactly** the two keys `W` and `B` (the "two peaks"): `W` is
  the `(V,V,V)` target logit tensor as nested Python lists and `B` the `(VC,)`
  bias. Values are the checkpoint's float32 numbers.
- `fitted` is boolean `true`.

The verifier `json.load`s the file and checks the exact key set, the two-peak
values (within float tolerance) and the `revision`.

---

## Summary of exact outputs / edge cases hidden probe

- `ckpt_reader` byte-exact np on shipped + a hidden checkpoint with a different
  vocab size/dims/max_gen/revision.
- `generate.py` re-run on fresh hidden prompts (≥2 ids), token-exact.
- `speculative.py` on hidden prefix/target/K (K can exceed remaining target;
  a fully-accepted draft-greedy target; short targets; K=1) — exact counts,
  result, and per-block verdicts. Off-by-one in acceptance/context is the trap.
- `retrieve.py` on hidden corpora (duplicate docs, empty doc, empty query, >5
  docs) — exact ranking/cosine/selected/fifth, revision pinned.
- `model.pkl` reloadable, correct shapes & values.
- `params.json` exact key layout / float values / revision.

There is **no network**; everything is local to this container.