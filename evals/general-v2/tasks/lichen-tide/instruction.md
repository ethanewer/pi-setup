# Lanternline NOC — Log Triage & Alerting

You are the on-call engineer for **Lanternline**, a fictional CDN operator.
The night shift needs a triage tool that scans structured log files against a
rule set and emits two JSON artifacts with EXACT schemas: a summary alert
file and a full event report. Everything runs offline in `/app` with Python
3.12 available as `python3`.

You must build a **reusable** tool: the verifier re-runs your program,
unchanged, on brand-new rule sets and logs that follow the same contract, so
your logic must be fully general — never hard-code to the provided files.

## Log line format

Every log file is line-oriented. A line is **well-formed** if and only if it
matches this grammar:

```
[YYYY-MM-DDTHH:MM:SSZ] LEVEL <message...>
```

- The bracketed UTC timestamp is a single token.
- `LEVEL` is exactly one of the five tokens `DEBUG`, `INFO`, `WARN`,
  `ERROR`, `CRITICAL` (severity order, lowest to highest).
- `<message...>` is the free-text remainder of the line.

Any other line — blank lines, missing brackets, unknown level tokens, wrong
timestamp shapes, etc. — is **ignored entirely**: it is never scanned and
never counts for anything.

Within a message, client addresses appear as whitespace-delimited tokens of
the form `client=<IP>`. A line may carry zero, one, or several such tokens.

## Rule set format

A rules JSON document:

```json
{ "rules": [
    { "id": "...", "keyword": "...", "min_level": "WARN", "threshold": 4, "severity": "high" }
] }
```

- `keyword` is a **literal substring** (NOT a regular expression) matched
  against the whole raw line.
- `min_level` is one of the five level tokens; a line counts for the rule
  only when the line's level is `>= min_level` in the severity order above.
- Rule ids are unique within a rule set; if duplicated, only the **first**
  definition is used.

### Defaults and malformed rules (probed by the grader)

- Missing or non-string `keyword` → the rule matches nothing.
- Missing `threshold` → defaults to `0` (such a rule fires even with 0
  matches, since `0 >= 0`).
- Missing `severity` → defaults to `"info"`.
- Missing or unknown `min_level` → treated as `DEBUG` (matches every level).
- A rules file that is missing, unparseable as JSON, or whose `rules` value
  is not a list → **zero rules**: the tool must still run and emit valid
  (empty) artifacts.
- Missing, unreadable, or empty log files contribute no matches (a missing
  log file argument is an error only if you cannot open it — treat an
  unopenable file as contributing nothing and continue).

## Deliverables (all required)

1. `/app/triage.py` — a runnable Python program:

   ```
   python3 /app/triage.py <rules.json> <alert_out.json> <report_out.json> <log1> [log2 ...]
   ```

   It applies the rules to the given log files (in argument order) and writes
   the two artifacts to the given output paths. It must work on any inputs
   conforming to the format above.

2. `/app/alert.json` and `/app/report.json` — the artifacts your program
   produces on the provided fixtures:

   ```
   python3 /app/triage.py /app/rules.json /app/alert.json /app/report.json \
       /app/logs/gateway.log /app/logs/audit.log
   ```

## Semantics (implement exactly)

For each rule, scan every log file argument (in argument order), every line
(in file order); a **well-formed** line *matches* the rule when the
`keyword` is a substring of the raw line AND the line's level is
`>= min_level`.

- **matches** = number of matching lines for that rule across all given
  files.
- **ips** = the sorted (lexicographic), de-duplicated list of `client=<IP>`
  values taken from matching lines only. A matching line with no
  `client=` token adds no IP.
- A rule **fires an alert** when `matches >= threshold`.

## Output schemas — exact keys, exactly

`<alert_out.json>`:

```json
{
  "timestamp": "<ISO-8601 UTC string, e.g. 2027-05-11T09:00:00Z>",
  "alerts": [
    { "id": "auth_failure", "severity": "high", "matches": 5, "ips": ["10.20.4.7"] }
  ]
}
```

- `alerts` contains ONLY the firing rules, in rule-set order, each with
  exactly the keys `id`, `severity`, `matches`, `ips`.

`<report_out.json>`:

```json
{
  "timestamp": "<ISO-8601 UTC string>",
  "events": [
    { "rule": "auth_failure", "client": "10.20.4.7", "line": "<full raw line>" }
  ],
  "statistics": {
    "<rule id>": {
      "id": "...", "keyword": "...", "min_level": "...", "threshold": 4,
      "severity": "...", "matches": 5, "unique_ips": 1, "ips": ["..."]
    }
  }
}
```

- `events` contains one entry for **every** matched rule/line pair, ordered:
  files in argument order, lines in file order, and for each line the
  matching rules in rule-set order. `client` is the **first** `client=`
  token on the line, or `null` when the matching line has none. `line` is
  the full raw line without its trailing newline.
- `statistics` contains an entry for **every** rule (even non-firing ones,
  with `matches: 0` and `ips: []`), keyed by rule id. Each entry has exactly
  the keys `id`, `keyword`, `min_level`, `threshold`, `severity`, `matches`,
  `unique_ips`, `ips`, where `unique_ips == len(ips)`.

## Edge cases probed by the grader

- **Both provided logs scanned together**, matches summed across files.
- **Malformed lines** (bad timestamp, unknown level like `NOTICE`, blank
  lines, no brackets) — ignored even when the keyword appears in them.
- **Level boundary**: a line at exactly `min_level` counts; one level below
  does not.
- **Zero-threshold rules** fire with `matches: 0` and `ips: []`.
- **Multiple `client=` tokens on one line** — all contribute to `ips`; the
  event records the first as `client`.
- **Rules with defaults applied** (missing `severity` / `threshold` /
  `min_level`, or a non-string `keyword`).
- **A garbage rule set** (valid JSON, `rules` not a list) — empty but valid
  outputs.
- **Empty log files** and rule sets whose nothing fires.

## Constraints

- Do not modify `/app/rules.json` or anything under `/app/logs/` (the
  verifier checks their integrity).
- No network access at verify time; standard library only.
- The verifier runs `/app/triage.py` unchanged on hidden inputs; do not
  hard-code file names or the visible contents.
