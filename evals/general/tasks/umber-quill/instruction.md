# Incident log-analysis workspace

You have been dropped into `/app` containing a set of **fixtures** you must read
but **not modify**:

- `/app/events.ndjson` — newline-delimited JSON log events.
- `/app/traces.txt` — a text log of stack traces.
- `/app/lines.txt` — free-form log lines mixing IPs and timestamps.
- `/app/activity_a.jsonl` and `/app/activity_b.jsonl` — two JSON-lines activity
  logs for an incident investigation.

Your job is to write two **executable** Python programs under `/app` and run them
to produce a set of deterministic output artifacts. The programs must be generic
(they will be re-run by the grader on fresh files that look exactly like the
fixtures below), so every path they take is given as a command-line argument —
never hard-code the fixture names `events.ndjson`, `traces.txt`, `lines.txt`,
`activity_a.jsonl`, `activity_b.jsonl`.

Deliverables you must create in `/app`:

- `/app/logproc.py` — a CLI program with three subcommands (documented below).
- `/app/respond.py` — an incident-response CLI (documented below).
- `/app/logs/round1.out`, `/app/logs/round2.out`, `/app/logs/round3.out`
- `/app/logs/frames.json`
- `/app/logs/dates.tsv`
- `/app/incident.json`

Do not create or modify anything else under `/app`. Do **not** touch the six
fixture files above.

---

## 1. `/app/logproc.py`

A script with the invocation `python3 /app/logproc.py <subcommand> <input> <output>`.

### 1a. `rounds` — group-sort + fixed-round partitioning

`python3 /app/logproc.py rounds <eventfile> <outdir>`

Read `<eventfile>` as **JSON Lines**. Each line must parse as a JSON object and
carry **all** of these fields: `id` (string), `ts` (ISO-8601 timestamp with
microsecond precision, e.g. `2026-04-01T00:00:00.000001Z`), `severity`, `runner`,
and `value` (integer). Any line that is not valid JSON, or that lacks any of the
required fields, is **silently skipped** (the fixture `events.ndjson` deliberately
contains one malformed line and one record missing `value`).

Group the surviving records by their `id`. Within each group sort strictly by
`ts` ascending. To break ties between identical `ts` values, keep their relative
input order (a **stable** sort); nothing else changes — each input record appears
at most once in the output.

Partition **every group** (independently) into exactly three buckets:

- the first `n // 3` records (where `n` is that group's record count) go to
  **round 1**,
- the last `n // 3` records go to **round 3**,
- every remaining middle record goes to **round 2**.

Write three output files `<outdir>/round1.out`, `<outdir>/round2.out`,
`<outdir>/round3.out`. Each output file contains the **original raw text lines**
(verbatim — byte-for-byte what was in the input file, not a re-serialization)
of the records assigned to that round, one record per line, joined by a single
`\n` with a trailing newline after the last line (an empty file is fine if no
records land in that round). Records are ordered by **ascending group `id`**
(string sort), and within a group by ascending `ts` (stable).

### 1b. `frames` — split a stack-trace log into frames

`python3 /app/logproc.py frames <tracefile> <outfile>`

Read `<tracefile>`. A trace begins on a line whose stripped content starts with
`TRACE:` followed by the trace name. The lines belonging to that trace are the
lines whose stripped content starts with `frame:`; each such line is one frame.
Any line that starts with neither `TRACE:` nor `frame:` (for example `# comment`
lines) is **ignored** and does not belong to any trace.

For each `frame:` line: remove the literal `frame:` prefix, strip surrounding
whitespace, and if the remaining text contains `::` keep **only the part before
the first `::`** (stripped again). The result is a single call-site string.

Write `<outfile>` as JSON — an array of `[trace_name, [frame_string, ...]]`
entries in the order the traces and frames appear in the input. Example shape:

```json
[["tibo",["init_sched","queue_pop","zephyr_cache"]],["echo",["rebind_session"]]]
```

### 3. `dates` — last date on lines that contain a valid IP

`python3 /app/logproc.py dates <linesfile> <outfile>`

Read `<linesfile>` line by line. A line is considered only if it contains at
least one **valid IPv4 address**. A valid IPv4 is four decimal octets joined by
dots, each octet `0..255`, with **no leading zeros** (`203.0.113.55` is valid;
`999.999.0.1` and `010.1.2.3` are not). Lines with **no** valid IP are never
output, regardless of what dates they contain.

For each qualifying line, find **every** ISO-8601 date-time token of the form
`YYYY-MM-DDTHH:MM:SS` followed by an optional `.ffffff` fractional part and a
trailing `Z` (e.g. `2026-04-01T00:00:00Z` or `2026-04-01T00:00:00.123Z`). Among
the date tokens on that line, keep **only the last one** (the token appearing
closest to the end of the line).

Write `<outfile>` as tab-separated lines — one per qualifying line — of the
form `<1-based-line-number>\t<last-date>`, in line order:

```
1	2026-01-03T00:00:00.000Z
```

(with a trailing newline). Lines with a valid IP but no date are skipped.

---

## 2. `/app/respond.py` — incident-response CLI with IP validation

Signature:

```
python3 /app/respond.py <ip> <logA> <logB> [outfile]
```

`<ip>` is the target IPv4. `<logA>` and `<logB>` are two JSONL activity files
(each line is a JSON object with `ts`, `ip`, `token`, `level`). `[outfile]` is
optional and defaults to `/app/incident.json`.

**Validation first**: if `<ip>` is not a valid IPv4 (four `0..255` octets, no
leading zeros), the script must print the exact text `INVALID_IP` on its own line
to stdout and exit with a **non-zero** exit code (do not read or write any other
files in that case).

For a valid IP, read both activity logs and keep every event whose `ip` field
equals the target. Records that repeat the **same `(ts, token)` pair** across the
two logs are counted **once** (deduplicated by `(timestamp, token)`). Then sort
the surviving records by `(timestamp, token)` lexicographically.

Write `[outfile]` as a JSON object with exactly these keys:

```json
{
  "target_ip": "<ip>",
  "occurrences": <count>,
  "tokens": ["<token in (ts,token)-sorted order>", ...],
  "start": "<ts of earliest record>",
  "end": "<ts of latest record>"
}
```

If the target IP appears nowhere, `occurrences` is `0`, `tokens` is the empty
list, and both `start` and `end` are `null`.

The report must be deterministic: same inputs always produce identical output.

---

## What the grader checks

The verifier re-runs `python3 /app/logproc.py` and `python3 /app/respond.py` on
fresh hidden files (malformed JSON records, duplicate microsecond timestamps,
duplicate records, invalid-octet and leading-zero IPs, multiple dates per line,
`::`-style frame prefixes, comment lines, an empty incident target, and invalid
IP rejection) and compares against exact expected outputs. It also confirms the
artifacts under `/app/logs/` and `/app/incident.json` match what your own
programs produce on the fixtures. Keep formats exactly as specified: raw-line
preservation in `round*.out`, `[trace-name,[frames]]` array in `frames.json`,
`lineno\tdate` rows in `dates.tsv`, the four-key incident schema, and the
`INVALID_IP` + non-zero exit contract.