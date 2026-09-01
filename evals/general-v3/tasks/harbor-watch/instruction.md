# Harbor Watch — fetch live duty-roster calendars and summarize watches

You are on the night desk at **Harbor Watch**, a ferry-terminal operations
office. You must write a single Python program `/app/solve.py` and run it so it
produces `/app/answer.json`.

The program is executed by the verifier on the provided **primary** case in
`/app/data` **and** on several **hidden** cases (same layout, different
terminals, crew, tokens, base dates and watches), so it must be fully
**general**: discover everything from the case directory it is given, never
hard-code names, tokens or numbers.

## Deliverables (both required)

1. `/app/solve.py` — the pipeline program.
2. `/app/answer.json` — the summary your program produces when run on the
   primary case (`/app/data`).

## Invocation

```
python3 /app/solve.py --case <CASE_DIR> [--url <http://127.0.0.1:PORT>] --out <RESULT_JSON>
```

- `--case`: a case directory. The primary case is `/app/data`. Required.
- `--url`: base URL of a **live** roster service that is already running. When
  omitted, your program must start the service itself (see below).
- `--out`: path where the summary JSON is written.

The verifier starts **fresh** roster services and passes a fresh `--url` for
every case (including hidden ones). Your program must therefore **fetch over
HTTP** — reading or copying pre-existing calendar files is not acceptable and
will fail the freshness check.

## Case layout

Every case directory contains exactly:

```
<CASE_DIR>/
  roster/service_config.json     roster service config (terminal, token, crew)
```

## Part 1 — Fetch the crew's calendars (live service, token auth)

`/app/tools/roster_service.py` is an HTTP server with these endpoints:

- `GET /health`              -> 200 "ok" (no auth needed)
- `GET /roster/<key>.ics`    -> that crew member's live watch calendar (200)

Every roster request **must** carry the header
`Authorization: Bearer <token>`, where `<token>` is
`service_config.json["auth_token"]`. Requests without the correct bearer token
get `401`.

The config lists crew as `service_config.json["crew"]`, an array of objects
each with `"key"`, `"display"` and `"watches"`. Fetch **every** crew member
listed in the config (there are always exactly two, and either one may have an
empty watch list). Save the body of each `/roster/<key>.ics` response to
`<CASE_DIR>/out/<key>.ics`.

Freshness rule: each served calendar embeds a random, per-process
`X-HARBOR-RUN` id that exists **only in a running service process**. A
calendar written by hand or copied from disk will never match a freshly served
one, so your program must genuinely request the service over HTTP.

When `--url` is given, use it directly. When it is omitted, launch the service
yourself:

```
python3 /app/tools/roster_service.py --config <CASE_DIR>/roster/service_config.json --port 0 --outdir <DIR>
```

read the `HARBOR_WATCH_UP port=NNNN sid=...` line from stdout to discover the
real port, set `base_url = http://127.0.0.1:<port>`, and wait until `/health`
responds before fetching.

## Part 2 — Summarize the fetched calendars

Parse each **fetched** ics (the bytes you saved in Part 1). Each calendar
contains zero or more `BEGIN:VEVENT ... END:VEVENT` blocks, each with exactly
one `DTSTART:YYYYMMDDThhmmss` line and one `DTEND:YYYYMMDDThhmmss` line. All
watches fall within a single day.

Define `minutes(t)` for a `YYYYMMDDThhmmss` value `t` as
`int(t[0:8])*1440 + int(t[9:11])*60 + int(t[11:13])`.

Compute, per crew member (in config order):

- `events`: number of VEVENT blocks.
- `first_start`: the lexicographically smallest `DTSTART` value (raw string,
  e.g. `"20320502T063000"`), or `null` when there are no events.
- `last_end`: the lexicographically largest `DTEND` value, or `null`.
- `busy_minutes`: sum over events of `minutes(DTEND) - minutes(DTSTART)`.

And one combined number:

- `overlap_minutes`: for every unordered pair of **distinct** crew members
  (i before j in config order), and every pair of events (one from each), sum
  the positive intersection `min(minutes(end_i), minutes(end_j)) -
  max(minutes(start_i), minutes(start_j))` when it is greater than zero.
  Touching events (one ends exactly when the other starts) contribute 0.

## Result summary

Write `<RESULT_JSON>` (the value of `--out`) as:

```json
{
  "task": "harbor-watch",
  "terminal": "<terminal from config>",
  "crew": ["<key1>", "<key2>"],
  "calendars": {
    "<key>": {
      "events": <int>,
      "first_start": <string|null>,
      "last_end": <string|null>,
      "busy_minutes": <int>
    }
  },
  "overlap_minutes": <int>
}
```

`calendars` has one entry per crew member keyed by `key`. All counts are exact
integers; the verifier compares against an exact reference computed from the
**served** calendars, so parse the fresh bytes, not anything pre-existing.

## Edge cases the hidden cases exercise

- A crew member with an empty `watches` list (valid empty ics; events 0,
  `first_start`/`last_end` `null`, `busy_minutes` 0).
- Overlapping watches between the two crew members (counted), and
  back-to-back/touching watches (not counted).
- Nested and duplicate-time watches; several watches per day; different base
  dates and tokens per case.
- The service rejects missing/wrong bearer tokens with 401 — always send the
  token from the config of the case you are processing.

## Constraints

- Do not modify anything under `/app/` other than creating `/app/solve.py`,
  writing `/app/answer.json`, and writing `<CASE_DIR>/out/` files.
- Do not edit `/app/tools/roster_service.py`.
- No network access beyond the local service; Python 3.12 standard library
  only.
- Hidden cases have different tokens, terminals, crew keys, base dates and
  watch tables — generalize.

## Acceptance

The verifier executes `/app/solve.py` on the primary case and on each hidden
case (fresh service, fresh `--url` each time), then checks for every case:
(a) every crew member's saved `<key>.ics` byte-matches a calendar freshly
served by a live service instance (freshness + token check); and (b) the
summary JSON equals an exact reference computed from the served calendars.
Produce both deliverables.