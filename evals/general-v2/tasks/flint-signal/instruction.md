# Helix Build Grid — CI Audit Alerts

You are the pipeline-integrity engineer for **Helix Build Grid**, a fictional CI
provider. Your job: write a rule-driven scanner that turns build/deploy logs into
an alert summary and a per-rule report with an **exact JSON schema**. The
verifier re-runs your scanner on hidden inputs and checks the output JSONs
key-for-key, so the schemas and semantics below are a hard contract.

## Environment

- Working directory: `/app`. It already contains the log fixtures
  `/app/logs/build.log` and `/app/logs/deploy.log`. Python 3.12 is available as
  `python3`.
- **Do not modify `/app/logs/build.log` or `/app/logs/deploy.log`.**

## Deliverables (all four required)

1. `/app/pipeline_scan.py` — a runnable Python program with this interface:
   ```
   python3 /app/pipeline_scan.py [-r RULES] [LOG ...]
   ```
   - `-r RULES` (optional): path to a rules JSON. Defaults to `/app/rules.json`.
   - `LOG ...` (optional): log files to scan. Defaults to
     `/app/logs/build.log` and `/app/logs/deploy.log` (in that order).
   - Outputs ALWAYS go to the fixed paths `/app/alert.json` and
     `/app/report.json` (overwritten on every run).
   Produce the visible deliverables by running it with no arguments:
   ```
   python3 /app/pipeline_scan.py
   ```

2. `/app/rules.json` — the rule set (content pinned exactly below).

3. `/app/alert.json` — the alert summary produced on the visible fixtures.

4. `/app/report.json` — the per-rule report produced on the visible fixtures.

## Input log format

Every line is free text; there is no fixed grammar. Lines may carry zero or more
IPv4 dotted-quad addresses (e.g. `ip=10.44.2.19`). Trailing `\n` is stripped
before processing; CRLF logs work too.

## Rule semantics

A rules JSON is `{"rules": [ {rule}, ... ]}`. Each rule object:

```json
{"id": "some_id", "pattern": "python regex", "threshold": 3, "severity": "high"}
```

For each rule, in rules-file order, scan every line of every given log file
(files in argument order, lines in file order). A line **matches** when
`re.search(pattern, line)` succeeds.

- **matches** = number of matching lines across all given files.
- **ips** = the deduplicated set of IPv4 dotted-quad addresses appearing
  anywhere in the matching lines, sorted with the standard string sort
  (lexicographic). A matching line with no IPv4 adds nothing.
- A rule **fires an alert** when `matches >= threshold`.

A `rule` entry's `ip` (used in `events`) is the **first** IPv4 address in the
matched line, or `null` when the line carries none.

## Malformed-input handling (probed by hidden cases — never crash)

- A rule with a **missing or non-string `pattern`** matches nothing.
- An **unparseable `pattern`** (one that raises `re.error`) matches nothing.
- A rule with a **missing or non-integer `threshold`** defaults to `0`
  (so it fires even with zero matches).
- A rule with a **missing or non-string `severity`** defaults to `"info"`.
- A rule file that is **missing, unreadable, not valid JSON, not a JSON object,
  or lacks a `rules` list** yields **zero rules**: the scanner must still run
  and emit empty structures.
- Missing, unreadable, or empty log files contribute no matches.
- A rule that matches nothing still appears in `report.json`'s `statistics`.

## Pinned `/app/rules.json`

Create `/app/rules.json` with EXACTLY this content:

```json
{
  "rules": [
    {"id": "secret_exfil", "pattern": "credential", "threshold": 3, "severity": "high"},
    {"id": "artifact_tamper", "pattern": "checksum mismatch", "threshold": 2, "severity": "high"},
    {"id": "fork_bomb", "pattern": "process spike", "threshold": 1, "severity": "medium"},
    {"id": "stale_cache", "pattern": "cache miss", "threshold": 2, "severity": "low"},
    {"id": "telemetry_ping", "pattern": "heartbeat", "threshold": 10, "severity": "notice"}
  ]
}
```

## Output schemas (exact)

`/app/alert.json` — exactly the keys `timestamp` and `alerts`:

```json
{
  "timestamp": "2026-04-02T10:00:00Z",
  "alerts": [
    {"id": "secret_exfil", "severity": "high", "matches": 3, "ips": ["10.44.2.19", "10.44.2.20", "10.44.7.5"]}
  ]
}
```

- `timestamp`: an ISO-8601 UTC string matching
  `YYYY-MM-DDTHH:MM:SSZ` (e.g. from `datetime.now(timezone.utc)`), same value
  in both output files for one run.
- `alerts`: ONLY the firing rules, in rules-file order. Each alert has exactly
  the keys `id`, `severity`, `matches`, `ips`.

`/app/report.json` — exactly the keys `timestamp`, `statistics`, `events`:

```json
{
  "timestamp": "2026-04-02T10:00:00Z",
  "statistics": {
    "secret_exfil": {"matches": 3, "unique_ips": 3}
  },
  "events": [
    {"rule": "secret_exfil", "ip": "10.44.2.19", "line": "2026-04-02T09:00:04Z runner=r7 stage=lint msg=\"credential prompt blocked\" ip=10.44.2.19"}
  ]
}
```

- `statistics` contains **every** rule keyed by its `id` (file order), each
  mapping to exactly `{"matches": <int>, "unique_ips": <int>}` — including
  non-firing rules with `{"matches": 0, "unique_ips": 0}`.
- `events` contains an entry for **every** (rule, matching line) pair — rules in
  rules-file order, files in argument order, lines in file order. Each event has
  exactly the keys `rule`, `ip`, `line` (`line` is the full line without its
  trailing newline; `ip` is the first IPv4 in the line or `null`).

## Constraints

- The verifier re-runs `/app/pipeline_scan.py` unchanged on hidden inputs
  (hidden rule files and/or hidden logs), so implement the general contract —
  do not hard-code counts.
- No network access at verify time; standard library only.
- Do not modify the provided logs in `/app/logs/`.
