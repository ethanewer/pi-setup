# Halcyon Grid — Edge Log Triage

You are the on-call analyst for **Halcyon Grid**, a fictional CDN operator.
Each shift ends with a machine-readable triage bundle: a compact **alert
summary** for the pager and a full **analysis report** for the audit trail.
Build a reusable triage program that turns raw edge logs plus a regex rule
set into those two JSON artifacts.

The verifier re-runs your program **unchanged** on brand-new rule sets and
logs that follow the same contract, so it must be correct on any conforming
input — including adversarial rules — not just the provided fixtures.

## Environment

- Working directory: `/app`. It already contains:
  - `/app/rules.json` — the shift's detection rule set.
  - `/app/edge/gateway.log` and `/app/edge/dns.log` — raw edge logs.
  - Python 3.12 is available as `python3` (standard library only, no network).
- **Do not modify `/app/rules.json`, `/app/edge/gateway.log`, or
  `/app/edge/dns.log`.**

## Rule set format

`/app/rules.json` (and every hidden rule set) is a JSON object:

```json
{"rules": [ {"id": "...", "pattern": "...", "threshold": 3, "severity": "high"}, ... ]}
```

- `pattern` is a Python regular expression applied with `re.search` against
  each **raw log line**.
- `id` identifies the rule; `threshold` is the minimum match count for the
  rule to fire an alert; `severity` is a free-form string label.

### Malformed-rule handling (probed by hidden cases)

- The root not being a JSON object, a missing or non-list `rules` key, or a
  **rules file that is missing or not valid JSON** means **zero rules**: the
  program must still run and emit the two outputs with empty structures.
- A rule that is not a JSON object, or has a missing/non-string `id`, is
  ignored entirely.
- A rule with a **missing or non-string `pattern`** matches nothing (treat it
  as an empty pattern for reporting).
- A rule whose `pattern` is **not a valid regex** (would raise `re.error`)
  matches nothing — never crash.
- A rule with a **missing or non-integer `threshold`** defaults to `1`
  (booleans are not integers). A rule with a missing or non-string
  `severity` defaults to `"medium"`.
- Missing or unreadable log files must abort with a non-zero exit; **empty
  log files are fine** and contribute no matches.

## Program interface

```
python3 /app/triage.py <rules.json> <out_dir> <log1> [log2 ...]
```

It writes exactly two files: `<out_dir>/alert.json` and
`<out_dir>/report.json` (create `<out_dir>` if needed).

## Detection semantics (implement exactly)

For each rule, scan **every** line of **every** given log file, in the order
the files were given on the command line:

- A line **matches** when `re.search(pattern, line)` succeeds on the raw line
  (newline stripped).
- `matches` for a rule = number of matching lines across all given files.
- For each matching line, extract the **source ip**: the first
  `ip=<dotted-quad>` token in the line (regex
  `ip=(\d{1,3}(?:\.\d{1,3}){3})`). A matching line with no such token
  contributes no ip. `ips` for a rule = the **sorted, de-duplicated** list of
  ips from its matching lines (plain string sort).
- A rule **fires an alert** when `matches >= threshold`.

## Output schemas (exact)

`<out_dir>/alert.json`:

```json
{
  "timestamp": "<ISO-8601 UTC, e.g. 2026-03-14T09:00:00Z>",
  "alerts": [
    {"id": "auth_fail", "severity": "high", "matches": 5, "ips": ["10.20.0.5", "203.0.113.7"]}
  ]
}
```

- `timestamp` is the current UTC time formatted exactly
  `%Y-%m-%dT%H:%M:%SZ`.
- `alerts` contains **only firing** rules, sorted by rule `id` ascending.
  Each entry has exactly the keys `id`, `severity`, `matches`, `ips`.

`<out_dir>/report.json`:

```json
{
  "timestamp": "<same format>",
  "events": [
    {"rule": "<rule id>", "ip": "<ip or null>", "line": "<raw line, newline stripped>"}
  ],
  "statistics": {
    "<rule id>": {
      "id": "<rule id>", "pattern": "<pattern>", "threshold": 3,
      "severity": "high", "matches": 5, "ips": ["10.20.0.5"]
    }
  }
}
```

- `events` has one entry for **every** matched rule/line pair, in scan order:
  files in command-line order, lines in file order, and — within one line —
  rules in their order in the rule set. `ip` is `null` when the line carried
  no `ip=` token; `line` is the raw line with its trailing newline stripped.
- `statistics` contains an entry for **every** accepted rule (even ones with
  zero matches, with `matches: 0` and `ips: []`), keyed by rule id. For a
  rule with a missing/non-string pattern report `"pattern": ""`; report the
  effective (possibly defaulted) `threshold` and `severity` as integers and
  strings.

## Deliverables (all required)

1. `/app/triage.py` — the program described above.
2. `/app/alert.json` — produced by running your program on the provided
   fixtures:
   ```
   python3 /app/triage.py /app/rules.json /app /app/edge/gateway.log /app/edge/dns.log
   ```
   (output lands at `/app/alert.json` and `/app/report.json`).
3. `/app/report.json` — as produced by the same run.

## Constraints

- The verifier runs `/app/triage.py` unchanged on hidden rule sets and logs
  with fresh output directories; do not hard-code to the fixture contents.
- Only the `timestamp` fields are allowed to vary between runs; every other
  value must be exactly as specified.
- Do not modify the fixtures in `/app`.
