# Flint-orchid: consolidate heterogeneous data sources

You are working on a data-consolidation pass for **Kestrel Metering Co.**'s asset
registry. Four unrelated feeds have arrived as raw fixtures under
`/app/data/`, and you must turn each into a machine-readable deliverable under
`/app/`. Work through all four; each is independently graded.

Read the exact paths and formats below carefully — every field name, key, and
byte layout matters. Do **not** modify anything under `/app/data/`.

Preinstalled libraries: `pypdf`, `beautifulsoup4` (with `html.parser`),
`rdflib`, `numpy`. Write ordinary Python 3 scripts that run from any working
directory and take absolute input/output paths as CLI arguments.

---

## Part 1 — PDF form fields → `/app/form_fields.json`

Parse `/app/data/registration_form.pdf` (a fillable PDF/AcroForm) with `pypdf`
and enumerate every fillable field. For each field:

- `name` — the field identifier (the `/T` value of the field),
- `label` — the field's alternate name (the `/TU`/tooltip value). If a field has
  no alternate name, fall back to the field name itself.

Write `/app/form_fields.json` containing a JSON **array** sorted ascending by
`name`, where each element is exactly

```json
{"name": "<field identifier>", "label": "<field label>"}
```

Also author a reusable tool `/app/parse_form.py` with signature

```
python3 /app/parse_form.py <input.pdf> <output.json>
```

which applies the exact same extraction (field list sorted by name, same
`name`/`label` semantics) to any fillable PDF and writes the JSON array to
`<output.json>`. It must handle forms with arbitrary numbers of text fields,
checkboxes, and radio groups, and must handle a field with no `/TU` (label falls
back to its name). The verifier will re-run it on fresh hidden form PDFs.

---

## Part 2 — HTML financial metrics → `/app/financials.json`

Parse `/app/data/financials.html` with BeautifulSoup and list the financial
metrics together with the row each appears in. The contract:

1. Only the `<table id="metrics">` is considered.
2. Row index is **1-based over every `<tr>`** in that table — header rows,
   spacer rows, and note rows all count toward the index (the header `<tr>` is
   row 1). Rows nested inside `<thead>`/`<tbody>` count exactly the same as
   direct children: index every `<tr>` element that appears within the table,
   walking the document in order from top to bottom.
3. A **metric row** is a `<tr>` that satisfies all of:
   - the row does **not** have CSS class `total` (totals must be excluded even
     though they look like metrics),
   - it has **exactly two `<td>` cells** (ignore `<th>` cells entirely — header
     rows can never be metrics),
   - the first `<td>` text is non-empty after stripping whitespace,
   - the second `<td>` text parses as a number after removing commas, a leading
     `$`, and surrounding whitespace (e.g. `1,600,000` → `1600000`,
     `$255,000` → `255000`; `n/a`, `days`, or `—` are **not** numbers, so such
     rows are skipped but still counted in the row indexes).

Write `/app/financials.json` as a JSON array sorted ascending by `row`, where
each element is exactly

```json
{"metric": "<first cell text, whitespace-stripped>",
 "amount": "<normalized number as string>", "row": <1-based row index>}
```

Also author `/app/parse_financials.py` with signature

```
python3 /app/parse_financials.py <input.html> <output.json>
```

applying the same contract to any HTML document (the `metrics` table search, the
`total`-class exclusion, the two-`td`-cell rule, number normalization, row
indexing, and row ordering). The verifier will re-run it on fresh hidden HTML
reports (including empty-label cells, spacer rows, totals rows, and non-numeric
amount cells).

---

## Part 3 — relationship query → `/app/query.rq` + `/app/results.csv`

`/app/data/relations.ttl` is a Turtle file using the namespace

```
PREFIX ex: <http://supplywire.example/>
```

It contains individuals (`ex:name`), organizations (`ex:name`), and `ex:worksAt`
links from an individual to the organization it belongs to. Some organizations
have no `ex:name`, and some individuals have no `ex:worksAt` link at all.

Write `/app/query.rq`, a SPARQL SELECT query that walks from each individual to
the organization it is linked to and projects **both names** into exactly the
two result variables **`?person`** (individual name) and **`?org`**
(organization name). Requirements:

- matching a row only when both the individual and the organization actually
  have names (nameless nodes produce no row),
- de-duplicate rows (`SELECT DISTINCT` or an equivalent),
- deterministic ordering: sort the result rows by `(?person, ?org)`
  lexicographically.

Then execute your query against `/app/data/relations.ttl` with `rdflib` and
write `/app/results.csv` as UTF-8 CSV, header line exactly

```
person,org
```

followed by the sorted, de-duplicated result rows. Use standard CSV quoting
(minimal quoting is fine; names contain no commas).

The verifier will re-run your **literal `/app/query.rq`** against fresh hidden
Turtle datasets (multi-membership people, shared organizations, people with no
links, duplicate statements, and even an empty graph) and compare the rows to an
independent recomputation.

---

## Part 4 — skinned-mesh decode → `/app/decode_mesh.py` + `/app/mesh_arrays.npz`

`/app/data/rigged_pump.bin` is a custom little-endian skinned-mesh binary in the
`KMSH` format, version 3. Its layout is:

```
bytes 0..4     magic "KMSH" (0x4B 0x4D 0x53 0x48)
bytes 4..8     version: uint32, must equal 3
bytes 8..12    vertex count V: uint32
bytes 12..16   bone count B: uint32
bytes 16..     V vertex records, 44 bytes each:
                 position   3 x float32   (bytes  0..12)
                 normal     3 x float32   (bytes 12..24)
                 texcoord   2 x float32   (bytes 24..32)
                 weights    4 x uint8     (bytes 32..36)  quantized 0..255
                 bones      4 x uint16    (bytes 36..44)  bone indices
then           B skeleton records, 30 bytes each:
                 parent     int16         (bytes  0..2)   root == -1
                 bind_pos   3 x float32   (bytes  2..14)
                 bind_quat  4 x float32   (bytes 14..30)  w,x,y,z
```

Write `/app/decode_mesh.py` with signature

```
python3 /app/decode_mesh.py <input.bin> <output.npz>
```

that decodes **any** such file (valid or malformed) into a NumPy `.npz` archive
with **exactly these keys, shapes, and dtypes**:

| key         | shape | dtype   |
|-------------|-------|---------|
| `positions` | (V,3) | float32 |
| `normals`   | (V,3) | float32 |
| `texcoords` | (V,2) | float32 |
| `weights`   | (V,4) | uint8   |
| `bones`     | (V,4) | uint16  |
| `parents`   | (B,)  | int16   |
| `bind_pose` | (B,7) | float32 |  (bind_pos x,y,z then bind_quat w,x,y,z per bone)

Edge cases your decoder **must** handle:

- `V` may be 0 (a valid mesh with zero vertices — arrays must still be written
  with the correct `(0, ...)` shapes).
- Malformed inputs must be rejected **cleanly**: bad magic, `version != 3`, or a
  file shorter than `16 + V*44 + B*30` bytes must make the program exit with a
  non-zero status, print an error to stderr, and **not** write the output file.

Run your decoder on `/app/data/rigged_pump.bin` to produce `/app/mesh_arrays.npz`
using those exact seven keys. The verifier will re-run `/app/decode_mesh.py` on
fresh hidden meshes (including a zero-vertex mesh and a large mesh) comparing
every array's shape, dtype, and values against an independent decode, and will
also feed it deliberately truncated / wrong-version / bad-magic files to confirm
it fails cleanly.

---

## Deliverables checklist

Everything below must exist under `/app/` when you finish:

- `/app/form_fields.json` and `/app/parse_form.py` (Part 1)
- `/app/financials.json` and `/app/parse_financials.py` (Part 2)
- `/app/query.rq` and `/app/results.csv` (Part 3)
- `/app/decode_mesh.py` and `/app/mesh_arrays.npz` (Part 4)

Do not modify `/app/data/`. Do not attempt to connect to any network.
