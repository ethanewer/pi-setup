# Inventory & Access-Report Turnaround

You are handed a messy data-processing shop for the fictional retailer **Cedarline
Outfitters**. Everything you need lives in `/app`. Your job is to turn raw web
access logs and a few scattered records into a set of EXACT report artifacts. The
verifier does not check *how* you got a number — it recomputes every artifact from
scratch on its own hidden inputs and compares, so your scripts must truly perform
the described computation and be runnable on brand-new data.

Read carefully: every file path, every command signature, and every output format
below is part of the contract. The hidden checks probe edge cases (malformed log
lines, no-error logs, CRLF / blank CSV lines, rows with wrong column counts),
so your parser logic must be robust to them exactly as specified.

---

## Fixtures already in `/app` (do not modify these files)

- `/app/sample_access.log` — line-oriented web access log (the "sample").
- `/app/sample_records.csv` — an item catalog for the CSV pipeline (the "sample").
- `/app/people_records.csv` — per-user account records with conflicting values.
- `/app/raw_processor.py` — a buggy CSV-processing script (see Part 2).

You may create any helper files you like, but the artifacts below MUST exist at
the required paths.

---

## Part 1 — Access-log summarization

Each request in an access log is exactly one physical line with this grammar
(the bracketed timestamp is a single token; the other five are whitespace-separated):

```
[YYYY-MM-DDTHH:MM:SS] <client_ip> <method> <path> <status> <size_bytes>
```

- `[YYYY-MM-DDTHH:MM:SS]` — a single bracketed ISO-local timestamp (no spaces).
- `client_ip` — a single non-whitespace token (e.g. dotted IPv4).
- `method`, `path` — single non-whitespace tokens.
- `status` — exactly 3 integer digits (100–599).
- `size_bytes` — a non-negative integer.

A line is a **request** if and only if it matches that exact grammar (leading
and trailing whitespace on the line is ignored). Any other line — blank lines,
lines without a bracketed timestamp, lines whose token sequence does not match,
`status` values with the wrong number of digits or out of range, extra trailing
tokens, etc. — is NOT a request and counts for nothing.

Build `/app/analyze_logs.py` with this interface:

```
python3 /app/analyze_logs.py <logfile>
```

It prints EXACTLY these two lines to stdout:

```
total_requests=<N>
unique_clients=<M>
```

- `<N>` = the number of request lines in `<logfile>`.
- `<M>` = the number of DISTINCT `client_ip` values among those request lines
  (count each distinct address once, regardless of how many requests it made).

Produce the deliverable by running it on the sample so that
`/app/log_report.txt` is exactly those two lines:

```
python3 /app/analyze_logs.py /app/sample_access.log > /app/log_report.txt
```

---

## Part B — Fix the CSV pipeline

The script `/app/raw_processor.py` reads an input CSV and writes a transformed
CSV, but it has a **newline-accumulation bug**: each `quantity` column keeps its
trailing newline because the value is never stripped, so the output file contains
one extra blank physical line per record. The pipeline must emit **exactly one
output line per input record** and nothing else.

Create a corrected copy at `/app/fixed_script.py` with the IDENTICAL command
interface so bytes into:

```
python3 /app/fixed_script.py <input.csv> <output.csv>
```

Rules for the corrected processor (must match exactly):

- Read the input CSV line by line.
- Trim each line of `\n` AND `\r` (so CRLF files work).
- Skip blank lines.
- Split on `,`. If the split does not yield exactly two columns, skip the line.
- `name` = first column, trimmed; `quantity` = second column, **trimmed of all
  surrounding whitespace/newlines**.
- If `name` or `quantity` is empty after trimming, skip the line.
- Emit one output line per kept record: `name.toLowerCase() + "," + quantity`
  followed by a single `\n`. No blank lines anywhere. Exactly one physical
  output line per kept input record.

Run the corrected pipeline over the sample catalog to produce the deliverable:

```
python3 /app/fixed_script.py /app/sample_records.csv /app/fixed_output.csv
```

Re-run it whatever way is convenient and INSPECT `/app/fixed_output.csv`: confirm
the transformation values are right and that there is exactly one line per input
record (no accumulated blank lines).

---

## Part C — Exact answer artifact

Build `/app/answer.py`:

```
python3 /app/answer.py <logfile>
```

It prints to stdout a SINGLE line: the timestamp of the **earliest request whose
status is `500`** in `<logfile>`. If no request has status `500`, it prints
`NONE`. The timestamp must be formatted exactly `YYYY-MM-DDTHH:MM:SS` (the
timestamp token from the log line). Compare timestamps lexicographically — ISO
timestamps sort correctly as strings.

Produce `/app/answer.txt` from the sample:

```
python3 /app/answer.py /app/sample_access.log > /app/answer.txt
```

The file must contain exactly that one line (plus its trailing newline is fine).

---

## Part D — Acceptance metric

Build `/app/metric.py`:

```
python3 /app/metric.py <logfile>
```

It prints to stdout a single JSON object with exactly these keys and types:

```json
{"accepted": <int>, "total": <int>, "acceptance_rate": "<rate>"}
```

- `accepted` = count of requests whose status is in the range 200–299 inclusive.
- `total` = total number of requests.
- `acceptance_rate` = `accepted / total` formatted with `"{:.3f}"` (exactly three
  decimal places, no extra digits). If `total` is 0, use `"0.000"`.

Produce `/app/metric.json` from the sample:

```
python3 /app/metric.py /app/sample_access.log > /app/metric.json
```

---

## Part E — Conflict report

`/app/people_records.csv` holds account records, one per row, format
`user,field,source,value`. The first line is a header and is skipped.

- Each `(user, field)` pair may have an authoritative **primary** row and a
  **backup** row. `source` is the literal token `primary` or `backup`.
- The chosen (merge) value for a `(user, field)` is: the `primary` value if a
  primary row exists for that pair, otherwise the `backup` value.
- A **conflict** occurs for a `(user, field)` pair only when BOTH a primary and a
  backup row exist AND their values differ. Pairs where a source is missing, or
  where both sources agree, are NOT conflicts.

Build `/app/merge_records.py`:

```
python3 /app/merge_records.py <input_csv>
```

It prints to stdout a JSON object in this EXACT shape (key names, list ordering,
and nested objects all matter):

```json
{
  "total_conflicts": <int>,
  "conflicts": [
    {
      "user": "<source value>",
      "field": "<field name>",
      "sources": [
        {"source": "primary", "value": "<primary value>"},
        {"source": "backup", "value": "<backup value>"}
      ],
      "winner": "<chosen value>"
    }
  ]
}
```

- `conflicts` lists every conflicting `(user, field)` in the order their FIRST
  row appears in the input file.
- `sources` lists primary first, then backup, each as `{source, value}`.
- `winner` is the chosen value (i.e. the primary value, since a conflict implies
  both sources exist).
- `total_conflicts` equals EXACTLY `len(conflicts)`.

Produce the deliverable from the sample:

```
python3 /app/merge_records.py /app/people_records.csv > /app/conflict_report.json
```

---

## Deliverables

Confirm all of these exist and are correct in `/app`:

- `/app/analyze_logs.py` and `/app/log_report.txt`
- `/app/answer.py` and `/app/answer.txt`
- `/app/metric.py` and `/app/metric.json`
- `/app/fixed_script.py` and `/app/fixed_output.csv`
- `/app/merge_records.py` and `/app/conflict_report.json`

The four scripts must be runnable on NEW log / CSV / records input supplied at
verification time with the exact commands above, and must implement the rules
exactly as documented. Do not modify the fixtures in `/app`.