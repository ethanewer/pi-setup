# Dunlin Fleet — telemetry threshold monitor

You are on the reliability crew for **Dunlin Fleet**, a fictional network of
edge telemetry devices. Each device pushes metric readings to a local log; a
small monitoring program must compare the readings against a rule set and emit
an **alert summary** and a **detailed report** in exact JSON schemas. The
verifier reruns your program on hidden rule sets and hidden logs, so implement
the documented semantics exactly — do not just hand-fix the visible files.

## Environment

- Working directory: `/app`. It already contains telemetry logs
  `/app/telemetry/edge-1.log` and `/app/telemetry/edge-2.log`. Python 3.12 is
  available as `python3`.
- **Do not modify anything under `/app/telemetry/`.**

## Deliverables (all four required)

1. `/app/monitor.py` — a runnable Python program:
   ```
   python3 /app/monitor.py [RULES] [LOG1 LOG2 ...]
   ```
   - If `RULES` is omitted it defaults to `/app/rules.json`.
   - If no `LOG...` arguments are given, it scans exactly
     `/app/telemetry/edge-1.log` and `/app/telemetry/edge-2.log` (in that
     order); otherwise it scans exactly the named files, in the order given.
   - Outputs always go to the fixed paths `/app/alert.json` and
     `/app/report.json` (overwriting whatever is there).

2. `/app/rules.json` — the rule set you author (contents specified below).
3. `/app/alert.json` — the alert summary produced by running the program with
   the defaults on the provided telemetry logs.
4. `/app/report.json` — the detailed report produced by the same run.

## Telemetry log format

Every line of a log file is in exactly one of two categories:

- **Reading:**
  `YYYY-MM-DDTHH:MM:SSZ device=<ip> metric=<name> value=<number>`
  e.g. `2026-03-01T09:00:00Z device=10.0.4.17 metric=cpu_temp value=87.5`
  where `<ip>` is a non-whitespace token, `<name>` matches `[A-Za-z0-9_]+`, and
  `<number>` is a decimal number (integer or with a fractional part, possibly
  negative). The line must match this shape exactly — no extra tokens, no
  extra whitespace variants.
- **Malformed:** anything else (blank lines, truncated lines, wrong tokens,
  non-numeric values). Malformed lines are ignored entirely and counted for
  nothing.

## Rule set

`/app/rules.json` is JSON of the form:

```json
{ "rules": [ { "id": "cpu_sizzle", "metric": "cpu_temp", "max": 85.0,
               "threshold": 3, "severity": "critical" }, ... ] }
```

A **reading matches a rule** when the reading's `metric` equals the rule's
`metric` AND its numeric `value` is **strictly greater** than the rule's `max`.

For each rule:
- **matches** = number of matching readings across all scanned files (in scan
  order).
- **ips** = the sorted, de-duplicated list of `device` values from matching
  readings only.
- A rule **fires an alert** when `matches >= threshold`.

### Malformed rule handling (probed by hidden cases)

- A rules file that is missing, unparseable, not a JSON object, or whose
  `rules` value is not a list yields **zero rules** — the program must still
  run and emit empty structures.
- A list element that is not a JSON object is skipped entirely (no statistics
  entry).
- A rule whose `id` is missing, empty, or not a string is skipped entirely.
- A rule with a missing or non-string `metric` is kept but can match nothing.
- A rule with a missing or non-numeric `max` is kept but can match nothing.
- A rule with a missing or non-integer `threshold` defaults to `0`.
- A rule with a missing or non-string `severity` defaults to `"info"`.
- If two rules share an id, the `statistics` map keeps the last one; events
  are still emitted for each rule independently.
- Missing or unreadable log files, or empty log files, are fine — they
  contribute no matches.

## Required output schemas

`/app/alert.json` — valid JSON with exactly these keys:

```json
{
  "timestamp": "<ISO-8601 UTC string>",
  "alerts": [
    { "id": "<rule id>", "severity": "<severity>", "matches": <int>, "ips": ["<ip>", ...] }
  ]
}
```

- `alerts` contains **only** the firing rules, in rule-set order.
- `timestamp` must be an ISO-8601 UTC timestamp string, e.g. produced with
  `date -u +%Y-%m-%dT%H:%M:%SZ` or the equivalent `datetime` call.

`/app/report.json` — valid JSON with exactly these keys:

```json
{
  "timestamp": "<ISO-8601 UTC string>",
  "events": [
    { "rule": "<rule id>", "device": "<ip>", "value": <number>, "line": "<full line>" }
  ],
  "statistics": {
    "<rule id>": {
      "id": "<rule id>", "metric": "<metric>", "max": <number or null>,
      "threshold": <int>, "severity": "<severity>",
      "matches": <int>, "unique_ips": <int>, "ips": ["<ip>", ...]
    }
  }
}
```

- `events` contains one entry for **every** matched rule/reading pair, in scan
  order (files in the given order, lines top to bottom, rules in rule-set
  order for each line). `value` is the numeric reading value (a JSON number);
  `line` is the full line with the trailing newline removed.
- `statistics` contains an entry for **every** kept rule (even non-firing
  ones, with `matches: 0`, `unique_ips: 0`, `ips: []`). `max` is the rule's
  numeric limit, or `null` when absent/non-numeric.
- Both files' `timestamp` values are written at run time (they will differ
  between runs; the verifier only checks the ISO-8601 shape).

## Rules you must author in `/app/rules.json`

Exactly these five rules (ids, metrics, limits, and severities are fixed; the
`threshold` values given here are required too):

| id | metric | max | threshold | severity |
|----|-------------|-------|-----------|----------|
| `cpu_sizzle` | `cpu_temp` | 85.0 | 3 | critical |
| `mem_pressure` | `mem_pct` | 92.0 | 2 | high |
| `disk_hothead` | `disk_temp` | 68.0 | 1 | medium |
| `link_flap` | `link_errors` | 50.0 | 5 | high |
| `fan_wail` | `fan_noise` | 62.0 | 9 | low |

Given the provided telemetry, the first three rules fire and the last two do
not — but the verifier recomputes every count from `/app/rules.json` and the
logs independently, so the numbers must genuinely follow from the semantics.

## Constraints

- The verifier runs `/app/monitor.py` **unchanged** on hidden rule sets and
  hidden log files, so do not hard-code the provided fixtures or file names.
- Standard library only; no network access at verify time.
- Do not modify anything under `/app/telemetry/`.
