# Million-row CSV transform with Vim

`/app/data.csv` is a single-line-per-record CSV with 1,000,000 data rows plus a
one-line header. Row format:

```
id,code
1,DP
2,CQ
...
```

- Line 1 is the header `id,code`.
- Each data row is two comma-separated fields: an integer `id` and a
  two-uppercase-letter `code`.
- Files use LF line endings; tokens are unique.

Your task is to transform the file **within Vim** — drive the edit with Vim
itself (a recorded macro, a `:normal`/Ex command, or a `:%s` substitution
applied over the whole buffer). Do not rewrite the file with a standalone text
parser.

## The transform

For every data row `id,code`:
- remove the comma,
- swap the two fields,
- join them with a hyphen: `code-id`.

The header line `id,code` stays exactly as is.

Example rows:
```
1,AB -> AB-1
12,CQ -> CQ-12
```

## Deliverables

1. `/app/data.csv` — the edited file: line 1 unchanged (`id,code`), and lines
   2..1,000,001 each equal to `code-id` for that source row.
2. `/app/report.txt` — a single line containing the integer
   `1000000`.

## Approach (this task rewards doing it with Vim discipline)

- **Design the compact transform before touching the big file.** Try the Vim
  substitution on a small scratch sample (say 5 copied rows) and confirm the
  result until the pattern is right before running it over the whole buffer.
  In Vim's default magic mode, numbered capture groups use `\(` `\)` and an
  integer class is `[0-9]`.
- **Measure the edit's resource limits and keystroke cost.** A single global
  `:%s/.../.../` is one pass over the buffer; re-recording a per-line `q`
  macro and replaying it 1,000,000 times is comparatively heavy typing and
  slower. Prefer the one-command form.
- **Verify exactly, not by eye.** Count the non-identity rows, confirm the
  header still matches, and check a spot row or two (e.g., first data line and
  last data line) before writing `report.txt`.

## How the verifier decides

The original source order is deterministic: row `i` (i = 1..1,000,000) carries
the code letters `chr(65+(i//26)%26)` and `chr(65+i%26)`. The verifier
regenerates the expected `code-id` lines from that same scheme and asserts:
- `/app/data.csv` equals the `id,code` header followed by the recomputed
  `code-id` line for every one of the 1,000,000 rows, exactly;
- `/app/report.txt` reads `1000000`.