# Drift Mantle — Network Access Log Census and Report Builder

You are given a single text access log at `/app/access.log` (a visible fixture).
Your job is to build ONE reusable Python program `/app/solve.py` that:

1. reads any plain-text access log,
2. extracts and counts strictly-valid IPv4 addresses,
3. classifies the log, and
4. writes five deliverable files into an output directory.

Everything the grader checks is produced by running `/app/solve.py`. Your
program must therefore be fully general: it must work identically on the visible
fixture and on fresh hidden logs that the grader feeds it. Do not hard-code the
visible log's contents.

## CLI contract for /app/solve.py

`/app/solve.py` takes exactly two command-line arguments:

```
python3 /app/solve.py <log_file> <output_dir>
```

- `<log_file>` is a path to one plain-text access log (UTF-8, may also contain
  arbitrary ASCII line noise).
- `<output_dir>` is the directory the program must write its deliverables into
  (create it if missing).
- Exit 0 on success; print a short error and exit non-zero on bad input.
- You must `chmod +x /app/solve.py`.

When you finish, `/app/solve.py` must already have been run on the visible log so
that the deliverables exist at these literal paths:

| Deliverable | Literal path | What it contains |
|-------------|--------------|------------------|
| report      | `/app/report.txt`  | headline stats + top-10 table (see below) |
| value       | `/app/value.txt`   | the single numeric result, nothing else |
| result.csv  | `/app/result.csv`  | exact columns: `ip,count,risk` |
| result.txt  | `/app/result.txt`  | per-row label-per-line format (see below) |
| image       | `/app/out.jpg`     | JPEG chart of the top rows |
| program     | `/app/solve.py`    | the general solver (the deliverable run on hidden logs) |

Do NOT modify `/app/access.log`.

## What counts as a valid IPv4 address

A valid address is a dotted quad of four octets where EVERY octet:

- is `0..255` in **normal decimal form**,
- has **no leading zero** (write `10` not `010`, `0` is fine alone),
- is **not part of a longer alphanumeric token** (adjacent letters or digits
  disqualify the address).

Build the octet pattern so it rejects out-of-range values (e.g. `256`, `999`),
rejects leading-zero values (e.g. `010`, `00`), and will not match a substring
inside a longer token such as `x192.0.2.1y`, `2192.0.2.1`, or `a192.0.2.1`.
A good octet fragment is:

```
(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])
```

and the full pattern should be wrapped so it cannot merge with adjacent
alphanumeric characters (use word-ish boundaries like `(?<![0-9A-Za-z])` at the
start and `(?![0-9A-Za-z])` at the end).

## Counting and derived statistics

Only **valid** addresses (per the rule above) are counted. Count each occurrence
of a valid address in the file — the same address appearing twice is counted
twice (one per occurrence). Invalid tokens (leading-zero, out-of-range, or
embedded in a longer token) are ignored entirely.

From the full text of the log compute:

- `total_lines` — number of lines in the file (treat a trailing line present without
  a final newline as one more line).
- `distinct` — number of distinct valid IPv4 addresses seen.
- `total_hits` — total number of valid-address occurrences.
- `flag` — the log's classification:
  - `PRISTINE` — every dotted-quad-shaped token is a clean valid address.
  - `OUT_OF_RANGE` — at least one dotted-quad-shaped token has an octet `> 255`.
  - `LEADING_ZERO` — no out-of-range token, but at least one dotted-quad-shaped
    token has a multi-digit octet that starts with `0`.
  For flag classification use a *permissive* dotted-quad tokenizer: it recognizes
  up-to-3-digit octets separated by dots and not part of a longer alphanumeric
  token (so `010.020.030.01`, `256.0.0.1` still get examined), even though such
  tokens do not themselves count as valid addresses. `OUT_OF_RANGE` takes
  priority over `LEADING_ZERO`.
- `verdict` — `GO` if `distinct >= 2` **and** `total_hits >= 5`, else `NO-GO`.
- `busiest` — the address with the most occurrences; ties broken by choosing the
  lexicographically smallest address. If there are no valid addresses, there is no
  busiest address.
- `risk` — for an address `a.b.c.d`, `risk = (a + b + c + d) % 10`.

Sort all distinct addresses descending by occurrence count, ties ascending
lexicographically. This ordered list is used everywhere below.

## report.txt — exact fixed-width layout

Write the file with EXACTLY this shape (replace values; keep spacing identical).
`IP` uses a left-justified width of 12, the others right-justified widths
(`#`=4, `HITS`=5, `RISK`=4):

```
FILE: <basename of log>
LINES: <total_lines>
IPS: <distinct>
HITS: <total_hits>
FLAG: <flag>
VERDICT: <verdict>
OBJ: <busiest ip, or "-" if none>
RESULT: <busiest ip>:<busiest count>:<busiest risk>, or "-" if none
<blank line>
   #  IP            HITS  RISK
<row for each of the top 10 rows, see below>
```

Rows are formatted with:

```python
"%4d  %-12s  %5d  %4d" % (rank, ip, count, risk)
```

The header line is:

```python
"%4s  %-12s  %5s  %4s" % ("#", "IP", "HITS", "RISK")
```

Only the **top 10** rows (highest counts, tie-ascending) are printed; fewer if
there are fewer distinct addresses. `basename` is the log file's name with no
directory part. The final line ends with a newline.

## value.txt — the standalone numeric value

`/app/value.txt` (or `<out_dir>/value.txt`) must contain ONLY the integer
`total_hits` followed by a newline. Nothing else — no labels, no units, no
spaces.

## result.csv — exact column set and order

Header row exactly:

```
ip,count,risk
```

then one row per distinct address in the sorted order above, all values written
as plain strings (e.g. `192.168.1.10,3,1`). No extra or reordered columns, no
missing columns.

## result.txt — label-per-line format

One line per distinct address, in sorted order, exactly:

```
<ip> name=<basename> count=<count> risk=<risk>
```

Example:

```
192.168.1.10 name=access.log count=3 risk=1
```

`name=` carries the log's basename (the filename key). Every row that appears in
result.csv must also appear here as a line, and vice-versa.

## out.jpg — the JPEG image

Generate a JPEG image of dimensions **640 x 480** that visually encodes the top
10 rows (or all rows if fewer) as bars — bar height proportional to each
address's count within a light background. The exact colors/bar widths are up to
you; the grader only requires a real JPEG of size 640x480. Use the `Pillow`
library (already installed).

## Fixtures and hidden logs

The visible fixture `/app/access.log` exercises normal addresses, a repeated
address, a leading-zero decoy, and an address listed near the tail. Hidden logs
the grader will feed `/app/solve.py` additionally contain, in various
combinations: multiple distinct addresses, repeated addresses, a large number of
distinct addresses (more than 10), out-of-range octets such as `256`/`999`,
leading-zero octets such as `010.020.030.01`, malformed line noise, addresses
embedded inside longer alphanumeric tokens (`x192.0.2.1y`), and address-looking
tokens that are invalid. Your program must behave deterministically on all of
them using the rules above and nothing else.

## What you must not do

- Do not read, guess, or hard-code the hidden logs or any grader output.
- Do not hard-code `/app/access.log`'s values into `/app/solve.py`.
- Do not read files under `/tests` — they are not present during your run.
- Keep the filenames, formats, widths, and column order exactly as specified.

## Definition of done

All of these exist and are correct: `/app/solve.py` (executable, general,
accepting `<log>` `<out_dir>`), `/app/report.txt`, `/app/value.txt`,
`/app/result.csv`, `/app/result.txt`, `/app/out.jpg` — each produced by running
the solver on the visible log.
