# sage-keystone — the Keystone Ledger extraction run

The **Keystone Ledger** bureau has handed you three closed-off data jobs.
Everything you produce lives under `/app`. There are three independent strands:
fillable-PDF form automation, a relationship walk over an RDF ledger, and a
binary skinned-mesh decode. You author **runnable programs** (not one-shot
answers) and you **run them yourself** to produce the derived results.

The three input fixtures are already present in `/app`:

```
/app/permit_form.pdf     a fillable PDF form (AcroForm controls)
/app/registry.ttl        an RDF ledger (Turtle) of recruits and firms
/app/hull_rig.bin        a skinned mesh in the SKM1 binary format (below)
```

---

## Strand 1 — Fillable form fields

`/app/permit_form.pdf` is a fillable form. You must write an extractor and
produce a report.

### `/app/extract_fields.py`

A Python program invoked as:

```
python3 /app/extract_fields.py <PDF_PATH>
```

It must open the PDF with `pypdf` (`from pypdf import PdfReader`) and print, to
**stdout only**, exactly one valid JSON array with zero trailing characters —
one object per interactive field the form declares. The objects are in the
exact order returned by `PdfReader(pdf).get_fields()`, and each object is:

```json
{"id": "<field name>", "label": "<field /TU tooltip, or empty string>"}
```

- `id` is the field name (the `/T` value; the key `get_fields()` returns for
  that field).
- `label` is the field's alternate/tooltip text (`/TU`). If the field has **no**
  `/TU` at all, `label` **must be the empty string** — do not use null or omit it.
- If the PDF has **no interactive fields at all**, print `[]`.

No extra output (no logos/no diagnostics/logs) may go to stdout.

### `/app/form_fields.json`

A JSON file whose content is exactly what `extract_fields.py` prints when run
on `/app/permit_form.pdf` — i.e. the same array of `{id,label}` objects in the
same order. Produce it by running the script:

```
python3 /app/extract_fields.py /app/permit_form.pdf > /app/form_fields.json
```

---

## Strand 2 — RDF ledger query

`/app/registry.ttl` is a Turtle RDF graph. Two namespaces are used:

```
ex:  <http://keystone.sage.example/seed/>
kbs: <http://keystone.sage.example/schema#>
```

The graph models a roster. A recruit is an RDF subject whose rdf:type is
`kbs:Recruit`. A recruit may be seconded to one or more firms via the property
`kbs:secondedTo`. People, firms and other entities carry human-readable names
via `kbs:name`.

### `/app/query.rq`

Write a single valid **SPARQL** SELECT query that walks from each recruit to the
firm(s) they are seconded to and projects **both names** into exactly the two
result variables:

```
SELECT DISTINCT ?recruit ?firm
```

where

- `?recruit` = the recruit's `kbs:name` string, and
- `?firm`    = the firm's `kbs:name` string.

Semantics the query must enforce exactly:

1. The subject of the walk must be **of rdf:type `kbs:Recruit`**.
2. It must have a `kbs:name` (recruits lacking a name are skipped).
3. It must be seconded (`kbs:secondedTo`) to some firm.
4. The firm must itself have a `kbs:name` (firms lacking a name are skipped).
5. `DISTINCT` — a recruit seconded to the *same* firm more than once yields one
   row.

Every such (recruit, firm) pair must appear exactly once. Do **not** filter by
any specific names or counts — the query must work on other registries with the
same schema.

### `/app/results.csv`

Run that query against `/app/registry.ttl` and store the result as
`/app/results.csv`:

- header line, exactly: `recruit,firm`
- one row per result; the recruit name, then a comma, then the firm name
  (names contain no commas).
- rows ordered **ascending by recruit name**, then **ascending by firm name**
  (a stable lexicographic sort, plain Python string comparison).

No quoting is required (names have no commas or quotes); do **not** add quotes.

You can execute the query with rdflib, e.g.:

```
python3 - <<'PY'
from rdflib import Graph
g = Graph(); g.parse("/app/registry.ttl", format="turtle")
# read /app/query.rq, run g.query(...), sort (recruit, firm), write csv
PY
```

---

## Strand 3 — Skinned mesh decode

`/app/hull_rig.bin` is a mesh+skeleton binary in the **SKM1** format defined
below. Write a decoder that reads any SKM1 file and emits a NumPy zip archive.

### The SKM1 binary format (all numbers little-endian)

```
Offset  Bytes   Field
0       4       magic "SKM1"
4       4       uint32 N  = number of vertices
8       4       uint32 B  = number of bones
12      4       uint32 K  = influences per vertex (>= 1 typical)
16      4       uint32 reserved = 0
```

Then, per vertex `i` in `0..N-1` (in order), exactly:

Then, the vertex block is N records laid end-to-end; for each vertex `i` in
`0..N-1`, reading `{x,y,z,u,v}` you read, in this exact order:

```
3  x float32  position  (x, y, z)
3  x float32  normal    (nx, ny, nz)
2  x float32  texcoord  (u, v)
K  x float32  bone weights   (w0..w_{K-1})
K  x int32    bone indices   (i0..i_{K-1})  0-based
```

Then, per bone `b` in `0..B-1` (in order):

```
3 x float32  bind-pose position (bx, by, bz)
4 x float32  bind-pose rotation quaternion (qx, qy, qz, qw)
1 x int32    parent bone index, or -1 if this bone has no parent
```

When `B == 0` there is no bone block at all (an "unanimated" mesh), and the
file ends right after the vertex block.

### `/app/decode_mesh.py`

A Python script invoked as:

```
python3 /app/decode_mesh.py <BIN_PATH> <NPZ_PATH>
```

It reads `<BIN_PATH>` and writes `<NPZ_PATH>` — a NumPy zip archive (
`import numpy as np; np.savez(path, **arrays)`) containing **exactly** these
keys and shapes/dtypes:

```
positions      (N, 3)  float32   per-vertex position
normals        (N, 3)  float32   per-vertex normal
texcoords      (N, 2)  float32   per-vertex uv
weights        (N, K)  float32   per-vertex bone weights
bones          (N, K)  int32     per-vertex bone indices
bind_positions (B, 3)  float32   per-bone bind pose position
bind_rotations (B, 4)  float32   per-bone bind pose quaternion
parents        (B,)    int32     per-bone parent (-1 root)
```

`N` and `B` come from the header; `K` from the header. You must replicate the
bytes exactly (no normalization, no reordering, no bone/weight filtering).
Weights need **not** sum to 1; copy what is in the file.

If the file is **malformed** — wrong magic, a header/block length that would
run past the end of the file, or a short/truncated body — the script must print
a single-line message `ERROR: <reason>` to **stderr** and **exit non-zero**.
It must not crash with a traceback on-malformed input, and must not write the
output file for a malformed input.

### `/app/mesh_arrays.npz`

The result of running the decoder on the visible mesh:

```
python3 /app/decode_mesh.py /app/hull_rig.bin /app/mesh_arrays.npz
```

Content: the arrays matching `N`, `B`, `K` encoded in `/app/hull_rig.bin`.

---

## Deliverables (all required, all under `/app`)

| Path                 | Kind                           |
|----------------------|--------------------------------|
| `/app/extract_fields.py` | runnable script (Strand 1) |
| `/app/form_fields.json`  | produced by running it on the visible form |
| `/app/query.rq`          | the SPARQL SELECT file (Strand 2) |
| `/app/results.csv`       | produced by running that query on the visible ledger |
| `/app/decode_mesh.py`    | runnable decoder (Strand 3) |
| `/app/mesh_arrays.npz`   | produced by running it on the visible rig |

Both scripts must be runnable with `python3 /app/<name>.py ...` from any
working directory, and both must be resilient to the malformed/edge inputs
described above (they will be exercised on fresh fixtures). Do not modify
`/app/permit_form.pdf`, `/app/registry.ttl`, or `/app/hull_rig.bin`.