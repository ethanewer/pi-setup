# zephyr-anchor — a compact bioinformatics batch

**Zephyr Labs** is setting up a fluorescent-reporter construct and needs a small
batch of reusable bioinformatics tooling. You must author four self-contained
Python programs under `/app`, then run each one to produce the required output
artifacts. Everything you need is already on disk as read-only fixture data;
**you must not modify or delete any file under `/app` that you did not create
yourself, and you must never touch anything under `/tests`.**

This is a batch — each deliverable is checked independently, and each one must
generalize to hidden inputs it has never seen (fresh DNA parameters, fresh FASTA
templates, fresh SMILES catalogs, and a fresh localhost API database).

---

## 1. `/app/window.py` — nucleotide composition constraint

A construct is only tolerated if, in **every** contiguous sliding window of a
fixed length, the fraction of the two G/C bases stays inside a stated percentage
range. Write a script:

```
python3 /app/window.py <out_path> <length> <window> <gc_min> <gc_max>
```

It writes to `<out_path>` a single line of exactly `<length>` characters,
containing only the letters `A C G T`, followed by a single trailing newline.
The string must satisfy: for **every** contiguous window of exactly `<window>`
nucleotides, the percentage computed as `100 * (count-of-G + count-of-C) /
<window>` lies within `[gc_min, gc_max]` **inclusive**.

- `length` and `window` are positive integers; `gc_min` and `gc_max` are
  percentages (floats) with `0 <= gc_min <= gc_max <= 100`.
- The inputs are **guaranteed feasible**: there exists an integer `k` with
  `ceil(gc_min*window/100) <= k <= floor(gc_max*window/100)`, so a valid string
  always exists. Use all four letters (`A C G T`), not just two.
- Output is a single line with no stray whitespace. Exit status `0` on success.

A correct reusable construction: if you tile a block of length `window`
that has exactly `k` G/C positions spread through it, then every
`window`-length contiguous substring is a rotation of that block and therefore
has exactly `k` G/C — so every window is automatically in range.

**Visible run to perform:** `python3 /app/window.py /app/window_out.txt 600 50 40 60`
(produce `/app/window_out.txt`). The 50-nucleotide GC fraction must lie in
`[40, 60]` across every window.

## 2. `/app/fasta.py` — FASTA pair emission with exact formatting

Write a program:

```
python3 /app/fasta.py <template.fa> <output.fa>
```

Reads `<template.fa>`, which contains **exactly one record** (a header line
starting with `>` plus one or more sequence lines; header description text is
ignored, and sequence may be mixed-case and multi-line). It writes to
`<output.fa>` a **FASTA pair file**: exactly two records, template-derived
headers, forward-first orientation:

```
>NAME                              <- record 1 header (first token after '>'; no leading '>')
<forward sequence, upper-cased, wrapped at 80 columns>
>NAME_rc                           <- record 2 header
<reverse complement, upper-cased, wrapped at 80 columns>
```

- `NAME` = the first whitespace-delimited token of the `>` header, with the
  leading `>` removed.
- Record 1 sequence = the template sequence, all uppercase, **forward**.
- Record 2 sequence = the **reverse complement** of the template, all uppercase.
  Reverse complement = reverse the string, then complement every base
  (`A<->T`, `G<->C`), case-insensitively.
- The output must contain **exactly two records** and **no blank lines
  anywhere**; every sequence line is uppercase `A/C/G/T`; no trailing whitespace
  on any line; the file ends with a single trailing newline.
- Wrapping: each sequence line is at most `80` characters (the last line may be
  shorter), and wrapping is identical for the reverse-complement output.

Hidden inputs are fresh single-record FASTA files (multi-line, mixed case,
GC-rich, palindromic-ish). Exit status `0` on success.

**Visible run to perform:** `python3 /app/fasta.py /app/template.fa /app/pair.fa`
(produce `/app/pair.fa`).

## 3. `/app/smiles.py` — SMILES -> RDKit conversion, None on invalid/empty

Write a program:

```
python3 /app/smiles.py <catalog.json> <report.json>
```

`<catalog.json>` maps sample ids to SMILES strings (some entries may be empty or
whitespace-only, and some are malformed). Write `<report.json>` as a JSON object
mapping each sample id to either:

- `{"valid": true, "atoms": <N>}` when the SMILES is a non-empty parseable
  molecule (N = the atom count, e.g. `mol.GetNumAtoms()`), or
- `null` when the SMILES is **invalid or empty/whitespace-only**.

Use RDKit (`from rdkit import Chem`; `Chem.MolFromSmiles(smi)`). The script must
**never** exit non-zero and must never raise an exception on any input — a bad
string simply maps to `null` in the report. Important nuance: `MolFromSmiles("")`
returns a *valid empty `Mol`* (with 0 atoms), but an empty/whitespace-only
SMILES is still considered invalid here and must be `null`. Detect blank input
before parsing.

Also expose a reusable function `convert(smiles)` that returns an RDKit `Mol`
for a valid non-blank SMILES and `None` for invalid or blank input.

**Visible run to perform:** `python3 /app/smiles.py /app/catalog.json /app/smiles_report.json`
(produce `/app/smiles_report.json`).

## 4. `/app/api_client.py` — spectra/sequence API client + member->employee join

A **localhost mock API server** is provided at `/app/api_server.py`. It is a
read-only fixture; do not change it. It serves a synthetic
fluorescent-protein database from a data directory.

```
python3 /app/api_client.py <data_dir> <out.json>
```

`<data_dir>` contains:

- `api.json` — array of `{"id","sequence","excitation_nm","emission_nm"}`
- `employees.json` — array of `{"id","name","department"}`
- `projects.json` — array of `{"id","department","member_ids":[..]}`
- `spec.json` — `{"donor":{"emission_min","emission_max"},
  "acceptor":{"excitation_min","excitation_max"},
  "sequence_ids":[..], "project_ids":[..]}`

Your program must:

1. **Start the local server** on a free `127.0.0.1` port:
   `python3 /app/api_server.py <data_dir>/api.json <port>`, then poll
   `GET http://127.0.0.1:<port>/health` until it returns `200`. This is the only
   network your client may ever touch — there is no outbound internet.
2. **Spectra selection.** For every protein in `api.json`, query
   `GET /api/spectra?id=<id>` (returns `{"id","excitation_nm","emission_nm"}`).
   Choose:
   - `donor` = the unique protein whose `emission_nm` lies within
     `[donor.emission_min, donor.emission_max]` (inclusive);
   - `acceptor` = the unique protein whose `excitation_nm` lies within
     `[acceptor.excitation_min, acceptor.excitation_max]` (inclusive).
   The data are seeded so exactly one protein satisfies each rule.
3. **Sequences.** For each id in `spec.sequence_ids`, query
   `GET /api/sequences?id=<id>` (returns `{"id","sequence"}`) and record the
   returned amino-acid sequence unchanged.
4. **Join.** For each id in `spec.project_ids`, look up the project in
   `projects.json`, and resolve **every** member id in `member_ids` to the
   employee row in `employees.json` whose `department` equals the project's
   `department`. The data guarantee every referenced member id resolves inside
   that department.

Write `<out.json>` exactly in this schema:

```json
{
  "donor":       {"id": "...", "excitation_nm": 0, "emission_nm": 0},
  "acceptor":    {"id": "...", "excitation_nm": 0, "emission_nm": 0},
  "sequences":   { "<id>": "<amino-acid sequence>" },
  "projects": {
    "<project id>": {
      "resolved_members": [
        {"member_id": "...", "employee_id": "...", "name": "...", "department": "..."}
      ],
      "unresolved_member_ids": []
    }
  }
}
```

- `donor`/`acceptor` must equal the `/api/spectra` payloads of the chosen
  proteins exactly (the three keys `id`, `excitation_nm`, `emission_nm`).
- `unresolved_member_ids` must be empty for every project.
- Exit status `0` on success. Never read `/tests`.

You may use `urllib.request`, `subprocess`, and `socket` (to pick a free port).

**Visible run to perform:** `python3 /app/api_client.py /app/data /app/api_report.json`
(produce `/app/api_report.json`).

---

## Deliverables checklist (all must exist under `/app`)

| Deliverable | produced by |
|---|---|
| `/app/window.py` | you write it |
| `/app/window_out.txt` | `python3 /app/window.py /app/window_out.txt 600 50 40 60` |
| `/app/fasta.py` | you write it |
| `/app/pair.fa` | `python3 /app/fasta.py /app/template.fa /app/pair.fa` |
| `/app/smiles.py` | you write it |
| `/app/smiles_report.json` | `python3 /app/smiles.py /app/catalog.json /app/smiles_report.json` |
| `/app/api_client.py` | you write it |
| `/app/api_report.json` | `python3 /app/api_client.py /app/data /app/api_report.json` |

## Success criteria

The verifier re-runs **each** of your four scripts on **fresh hidden inputs**
(a new window/length/GC case, a new FASTA template, a new SMILES catalog, and a
fresh localhost API database plus project/employee set) and checks the exact
behavior specified above. All four must generalize correctly; none may work only
for today's fixtures. Do not hardcode the visible data (`600`, today's template
sequence, the sample catalog, or today's protein ids) — the hidden inputs are
brand-new.