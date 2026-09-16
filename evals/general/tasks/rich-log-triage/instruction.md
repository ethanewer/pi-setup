Implement a deterministic log-triage reporter in `/app/triage.py` and an executable reproduction harness in `/app/repro_case.py`.

The supplied source directory `/app/source/` contains a UTF-8 JSONL event stream. Each non-empty line must be an object with exactly these fields: `id` (non-empty string, unique), `timestamp` (UTC ISO-8601 in the form `YYYY-MM-DDTHH:MM:SSZ`), `level` (one of `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`), `component` (non-empty string), `message` (non-empty single-line string), and optional `tags` (a non-empty list of non-empty strings). Reject malformed JSON, blank lines, missing or extra fields, wrong types, duplicate IDs, invalid timestamps, unsupported levels, empty strings, control characters (Unicode C0 `U+0000`–`U+001F`, DEL `U+007F`, and C1 `U+0080`–`U+009F`), and missing, empty, non-list, or malformed tags when `tags` is supplied. Do not partially report invalid input. An entirely empty input stream is valid and produces a zero-record report.

The CLI must be:

```text
python /app/triage.py --input PATH --output PATH
```

It must read only the named input, write the report only to the named output, return nonzero with a concise stderr diagnostic on any validation or I/O failure, and produce no interactive or environment-dependent output. The report is plain UTF-8 text with no ANSI escapes and exactly this structure:

```text
Log triage report
Records: N
Levels: CRITICAL=C, ERROR=E, WARNING=W, INFO=I, DEBUG=D
Components: name=count, name=count
Events:
[timestamp] LEVEL component: message
...
```

Use severity order `CRITICAL, ERROR, WARNING, INFO, DEBUG` in the Levels line, including zeroes. Components are aggregated over all records and ordered by descending count, then by the first record's position after event ordering, then lexicographically. Use `none=0` if there are no records. Events are ordered by timestamp ascending, with original input position as the stable tie-breaker. Render message text literally: square brackets, backslashes, quotes, and other ordinary punctuation must not become Rich markup or terminal control sequences.

Expose a small callable used by the harness (for example, `build_report(lines)`), but keep command-line parsing and file I/O separate from the pure transformation. Use Rich's noninteractive text/console facilities where useful, configured so output is deterministic and markup, color, hyperlinks, terminal discovery, and prompts are disabled. Do not use network access, current time, locale-sensitive formatting, or unordered iteration for user-visible ordering.

`/app/repro_case.py` must be executable without arguments, import and exercise your implementation against `/app/source/events.jsonl`, assert the key summary and literal-message behavior, and print exactly `REPRO_OK` on success. It must exit nonzero on failure. `/app/triage.py` is invoked as `python /app/triage.py`; its executable permission is not required. Do not modify files under `/app/source/`.
