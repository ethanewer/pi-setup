# Halcyon Gate — Triage Alert & Report Emission

You are on the network-operations desk of **Halcyon Gate**, a regional ISP. The
night's gateway and DNS audit logs need to be triaged by a rule set before the
morning review. Build a reusable triage program that scans logs against keyword
rules and emits two JSON artifacts with EXACT schemas. The verifier re-runs
your program on brand-new rules/logs and recomputes every count itself, so your
implementation must follow the contract below exactly.

## Environment

- Working directory: `/app`. It already contains the log files
  `/app/logs/gateway.log` and `/app/logs/dns.log`. Python 3.12 is available as
  `python3`.
- **Do not modify anything under `/app/logs/`.**

## Deliverables (all required)

1. `/app/triage.py` — a runnable Python program with this interface:
   ```
   python3 /app/triage.py [RULES] [LOG1 LOG2 ...]
   ```
   - If `RULES` is omitted it defaults to `/app/rules.json`.
   - If no `LOG...` arguments are given, it scans `/app/logs/gateway.log` and
     `/app/logs/dns.log` (in that order); otherwise it scans exactly the named
     files, in the order given.
   - Outputs always go to the fixed paths `/app/alert.json` and
     `/app/report.json`.

2. `/app/rules.json` — the rule set you author for the scenario (see below).

3. `/app/alert.json` and `/app/report.json` — the two artifacts your program
   produces **when run with no arguments** on the provided logs:
   ```
   python3 /app/triage.py
   ```

## Rule set

A rules file is JSON: `{"rules": [ { "id": ..., "keyword": ..., "threshold": ..., "severity": ... }, ... ]}`.

Author `/app/rules.json` with **at least** these five rules (exact ids and
keywords; choose thresholds as specified):

| id | keyword | threshold | severity |
|----|---------------|-----------|----------|
| `port_probe` | `port_probe` | 3 | high |
| `dns_tunnel` | `dns_tunnel` | 2 | medium |
| `cred_stuffing` | `cred_stuffing` | 2 | high |
| `beacon_1s` | `beacon_1s` | 4 | medium |
| `noisy_scan` | `noisy_scan` | 50 | info |

With the provided logs, `noisy_scan` must **not** fire (its match count stays
below its threshold); the other four fire as their counts warrant.

## Matching semantics (implement exactly)

Tokenize each log line by splitting on whitespace. A line **matches** a rule
when the rule's `keyword` appears as one of those whitespace-separated tokens
(exact token equality, case-sensitive). Scan every rule against every line of
every given log.

For each rule:

- **matches** = number of matching lines across all given logs.
- For a matching line, every token that starts with `from=` contributes the
  remainder after `from=` as a source IP (ignore empty remainders).
- **ips** = the lexicographically sorted, de-duplicated list of source IPs
  from matching lines only. A matching line with no `from=` token counts
  toward `matches` but adds no IP.
- A rule **fires an alert** when `matches >= threshold`.

## Output schemas (exact)

`/app/alert.json`:

```json
{
  "timestamp": "<ISO-8601 UTC, e.g. 2026-05-11T08:20:00Z>",
  "alerts": [
    { "id": "port_probe", "severity": "high", "matches": 4, "ips": ["10.9.8.9", "203.0.113.7", "203.0.113.9"] }
  ]
}
```

- `alerts` contains **only** firing rules, sorted by rule `id` ascending.
- `timestamp` must match `YYYY-MM-DDTHH:MM:SSZ`.

`/app/report.json`:

```json
{
  "timestamp": "...",
  "events": [
    { "rule": "port_probe", "ip": "203.0.113.7", "line": "<full original line>" }
  ],
  "statistics": {
    "port_probe": { "matches": 4, "unique_ips": 3, "ips": ["10.9.8.9", "203.0.113.7", "203.0.113.9"] },
    "noisy_scan": { "matches": 2, "unique_ips": 2, "ips": ["203.0.113.7", "203.0.113.8"] }
  }
}
```

- `events` has one entry for **every** matched (rule, line) pair, in scan
  order: rules in rule-file order, and within a rule the lines in file order
  across the given logs. `ip` is the value of the **first** `from=` token in
  the matching line, or `null` when the line has none.
- `statistics` contains an entry for **every** rule in the rules file (even
  rules with zero matches), each with exactly the keys `matches` (int),
  `unique_ips` (int), and `ips` (sorted list).

## Malformed-input handling (probed by hidden cases — never crash)

- A rule object with a **missing or non-string `keyword`** matches nothing but
  still appears in `statistics` with `matches: 0` and `ips: []`.
- A rule with a **missing or non-integer `threshold`** defaults to `0`.
- A rule with a **missing or non-string `severity`** defaults to `"info"`.
- A rules file that is **missing or not valid JSON**, or a top-level object
  without a `"rules"` list, yields zero rules: `/app/alert.json` must be
  `{"timestamp": ..., "alerts": []}` and `/app/report.json` must be
  `{"timestamp": ..., "events": [], "statistics": {}}`.
- Missing/unreadable/empty log files contribute no matches (but the program
  must still run and write both outputs).

## Constraints

- The verifier re-runs your program with hidden rules/logs and recomputes the
  expected artifacts independently, so do not hard-code to the provided files.
- No network access at verify time; standard library only.
- Do not modify `/app/logs/*`.
