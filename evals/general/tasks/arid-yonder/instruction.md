# Cormorant Transit — data sweep

You are modernising the passenger records for the **Cormorant Transit** shuttle
agency. The legacy export is stored in `/app/data` and mixes several ad-hoc
formats that all need to be parsed into clean, machine-readable outputs.

You must author a single Python program **`/app/parse.py`** that performs the
whole sweep, then run it on the shipped data so that the deliverable files land
at the exact `/app` paths given below.

## Deliverables (exact paths)

1. `/app/parse.py` — a runnable Python program (executable, `chmod +x`).
2. `/app/out.tsv` — the normalised per-passenger manifest (see "Outputs").
3. `/app/tree.json` — the reconstructed directory tree (see "Directory listing").
4. `/app/qdp.tsv` — the parsed table (see "QDP table").

## Program interface

`/app/parse.py` must accept **two command-line arguments**:

```
python3 /app/parse.py <input_dir> <output_dir>
```

Given an input directory it must write three files into the output directory
(creating it if needed): `out.tsv`, `tree.json`, `qdp.tsv`. The output file
names, formats, and column layout below are part of the contract and must match
exactly.

To produce the deliverables, run it against the shipped fixtures once:

```
python3 /app/parse.py /app/data /app
```

The same program must remain general: it will later be re-run by the verifier
against **other** input directories (fresh records, other preference files,
other listings, other tables), never only against `/app/data`.

## Inputs (all under `<input_dir>`)

### `records.tsv`

Tab-separated, one header row then one row per passenger. Columns, in order:

```
guest_id  attendee  address  date  lead_days
```

- `address` is a single TSV field whose street-number **line break** is encoded
  as the **two literal characters** backslash followed by `n` (`\n`), *not* a
  real newline:
  - line 1 = `<house number> <street name>`
  - line 2 = `<city> <postal-code>`
  - example cell: `742 Crimson Lane\nLarkspur 48622`
- `date` may be ISO (`2026-05-14`), US numeric (`05/20/2026` = month/day/year),
  or named month (`3 Jun 2026`, `Jun 3, 2026`).
- `lead_days` is a non-negative integer.

Nullable / masked value markers (in **any** numeric or date cell) are
`-`, `.`, `na`, `n/a`, `nan`, `null`, `none`, `missing`, `absent`, `nil`, and
the empty string — all treated **case-insensitively** as **absent data**. A
masked `date` or `lead_days` yields an empty field in the output.

### `prefs/` — preference fixtures in three different encodings

- `prefs/legacy.pkl` — a **python pickle** of a dict `{guest_id: constraint}`.
- `prefs/schedule.b64` — a **base64** blob that decodes to
  `guest_id:constraint` lines.
- `prefs/notes.txt` — plain `guest_id:constraint` lines.

Every passenger's constraint comes from exactly one of these sources. Any of
these files may be missing — in that case just use what is present. If no
source provides a constraint for a passenger, its preference is the literal
string `absent` and its source is `absent`.

### `listing` — a `tree -F` directory listing

Lines use box-drawing connectors (`├── ` / `└── `) and 4-column indentation
segments (`│   ` for a continued ancestor, `    ` for a plain ancestor).
Indentation depth = `(characters before the connector) // 4 + 1`. The first
line is the top-level directory (no connector).

`tree -F` appends one trailing marker to a name: `/` directory, `@` symlink,
`*` executable, `|` FIFO, `=` socket. A name with no trailing marker is a
regular file. Names may contain spaces, quotes, `!`, `#`, `( )`, `{ }`,
back-ticks, and non-ASCII letters — only the **final** character is a marker.

### `table.qdp` — a QDP-style ASCII table

Command lines start with `READ`, `SKIP`, `RES`, `TYPE`, `DECL`, `NUM`, `TIME`,
or `BINS`; these keywords must be recognised **case-insensitively** (the input
may use `read`, `res`, `skip`, …). A `#` at the start of a line begins a
comment/status line that is ignored. Everything else is a data row whose tokens
must all be numeric. `SKIP n` means the next `n` data/other lines are ignored.
Any non-numeric, non-command line is ignored. The table may be re-provided with
lowercase (or mixed-case) commands, so a parser that only matches uppercase
keywords is wrong.

## Outputs (written to `<output_dir>`)

### `out.tsv` (the manifest)

Tab-separated, header row then one row per passenger **in input order**:

```
guest_id  attendee  city  postal_code  date_iso  lead_days  preference  source
```

- `city`: the text on line 2 of the address minus the 5-digit postal code
  (leading/trailing whitespace trimmed). Empty when there is no line break or
  no city.
- `postal_code`: the 5-digit token on line 2 of the address. Empty when absent.
- `date_iso`: the date normalised to `YYYY-MM-DD`, or **empty** when the date is
  masked/unparsable.
- `lead_days`: the integer as text, or **empty** when masked/unparsable.
- `preference`: the decoded constraint for that passenger, or `absent`.
- `source`: the file the constraint came from (`legacy.pkl`, `schedule.b64`,
  `notes.txt`), or `absent`.

### `tree.json`

The reconstructed hierarchy as JSON. Every node is an object:

```json
{"name": "...", "kind": "dir", "children": [...]}
```

Dirs have `kind: "dir"` plus a `children` array (in listing order); non-dirs
have `kind` one of `file`, `exec`, `symlink`, `fifo`, `socket` and no
`children`. The root object is the top-level directory named on the first line.

### `qdp.tsv`

One row per data line, tokens tab-separated, integers printed without a
decimal point (e.g. `1.0` → `1`, `1.5` → `1.5`).

## What must NOT be modified

Do not modify or edit the files under `/app/data`. Only create
`/app/parse.py` and the three output files. Do not read from `/tests`.

## Constraints

- Use only the standard library (no third-party modules required).
- `/app/parse.py` must be self-contained and deterministic (no random
  ordering), so re-running it on the same inputs gives the same bytes.
- It must not hard-code the shipped rows/buildings — hidden runs use entirely
  different records, bindings, listings, and tables.
