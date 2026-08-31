# Relabel the ground-station telemetry feeds (headless vim)

The **Quartz Relay** ground-station operator archives raw telemetry feed files
that arrive from several stations. Before the feeds can be ingested, every
well-formed telemetry row must be relabeled into the archive layout. There is
no GUI on the relay node: the rewrite must be done with a **single headless
vim script** (using vim's own text-munging — substitution patterns, or macros
over the buffers) that can be replayed on any feed file.

## Environment

- Working directory: `/app`. It already contains the feed fixtures
  `/app/data/feeds/station-a.txt` … `/app/data/feeds/station-d.txt`.
- `vim` is installed. Do not modify or delete `/app/data/feeds/` (the
  verifier compares your outputs against them).

## Deliverables (all required)

1. `/app/apply_relabel.vim` — the headless vim script.
2. `/app/transformed/*.txt` — the relabeled copies of the four fixture feeds
   (`station-a.txt` … `station-d.txt`, same basenames), produced by running
   your script.

## Row shape and relabel rule

A **shapeable** telemetry row is a single line that matches **exactly**
(`^`…`$`, the whole line):

```
<YYYY>-<MM>-<DD>;<CODE>;<LABEL>
```

where:

- `<YYYY>`, `<MM>`, `<DD>` are digits, exactly 4 / 2 / 2 of them respectively
  (the shape is textual: `0000-00-00` is shapeable);
- `<CODE>` is exactly three characters `A`-`Z` (uppercase only);
- `<LABEL>` is non-empty and contains no `;` (any other characters — spaces,
  tabs, punctuation — are allowed and preserved);
- there are exactly two `;` separators; the line starts with the date (no
  leading whitespace) and nothing follows the label.

**Every shapeable row must be rewritten everywhere to:**

```
<LABEL> [<CODE>] <DD>.<MM>.<YYYY>
```

Note the full reorder: label moves to the front in brackets-free form, the
code goes into square brackets, and the date is reversed with dots
(`2025-01-07` → `07.01.2025`).

Every row that is **not** shapeable must be left **byte-for-byte unchanged**
— including blank lines, whitespace-only lines, lines with one or more than
two `;` separators, an empty label (`…;ABC;`), a lowercase or short/long code
(`…;abC;`, `…;FR;`, `…;A1B;`), a malformed date (`2025-1-07`, `2025-01-7`,
`x;…`), or leading whitespace before the date.

## Examples

Shapeable:
- `2025-01-07;ABC;uplink nominal` → `uplink nominal [ABC] 07.01.2025`
- `2025-06-30;MGN;v1.2 [ok]` → `v1.2 [ok] [MGN] 30.06.2025`
- `0000-00-00;NIL;placeholder` → `placeholder [NIL] 00.00.0000`

Unchanged (byte-for-byte):
- `2025-1-07;ABC;short month`
- `2025-01-08;zul;lowercase code`
- `2025-02-01;KIT` (only one `;`)
- `2025-02-02;PWR;` (empty label)
- `;KIT;leading separator`
- `2025-03-02;LOD;row;too;many` (three `;`)
- `   2025-03-01;LOD;indented date` (leading whitespace before the date)
- blank lines and whitespace-only lines

## The script's interface

It must run headless (no GUI) exactly like this:

```
vim -es -N -u NONE -i NONE -n -S /app/apply_relabel.vim
```

- With **no file arguments**, the script must relabel every `*.txt` file
  **directly under** `/app/data/feeds/` and save each result to
  `/app/transformed/<basename>` (same filename; create
  `/app/transformed/` if needed).
- The script must also work when **explicit file paths are passed as
  arguments** (`vim -es -N -u NONE -i NONE -n -S /app/apply_relabel.vim
  <file>...`); those are relabeled to `/app/transformed/<basename>` too. The
  verifier will replay it on hidden feed files this way.
- The source files must never be modified in place.

Run the script over the shipped fixtures so the four transformed files in
`/app/transformed/` exist before you finish.

## Constraints

- The verifier re-runs `/app/apply_relabel.vim` unchanged on freshly inserted
  hidden feed files (valid rows plus edge/malformed rows) and compares the
  results byte-for-byte, so the script must implement the rule above, not
  just have produced the four fixture outputs.
- No network, no GUI, nothing outside `/app` (besides the fixed `/app/data`
  fixtures being read).
