# iris-ember — Meridian meeting scheduler

## Objective

Meridian runs a small cadence of team sync meetings and keeps each attendee's
occupied time in **availability minutes**. Your job is to author a single
self-contained Python program, `/app/schedule.py`, that reads a directory of
availability minutes, finds the **earliest conflict-free slot** for a target
meeting (honouring a recovery buffer after meetings that end at a *late hour*),
emits a **standards-conformant iCalendar (.ics)** file for that slot, discovers
and drives a provided per-person schedule-producer tool to write one snapshot
file per attendee, and writes a short summary. It must never modify the input
files.

Run `/app/schedule.py` with **no arguments** to produce the deliverables at the
fixed paths under `/app` — that must always work. The program must **also**
accept a small command-line interface that the verifier uses to re-run it on
fresh availability sets:

```
python3 /app/schedule.py --avail <avail-dir> --out <out-dir>
```

- `--avail DIR` — a differently-populated availability directory laid out
exactly like `/app/availability` (one `config.json` plus one
`<attendee>.avail` file per attendee).
- `--out DIR` — the output directory where the deliverables are placed.

When these flags are given, the deliverables go to
`<out-dir>/earliest_slot.ics`, `<out-dir>/summary.txt` and
`<out-dir>/personals/<attendee>.txt` instead of the `/app` defaults, and the
per-person producer is still discovered and driven from `/app/tools/`. The
`--avail` input directory is strictly read-only for your program, exactly like
`/app/availability`. With no arguments both flags default to
`/app/availability` and `/app`.

## Platform / inputs

- Python 3.12. The `ics`, `python-dateutil` and `pandas` packages are already
  installed in the container.
- The attendee availability lives in `/app/availability/`:
  - `config.json` — the meeting request and scheduling rules,
  - one file per attendee named `<attendee>.avail`.
- The per-person schedule-producer tool lives somewhere under `/app/tools/`.
- **Never read or write `/tests`**: it is mounted read-only at verify time and
  is not part of your deliverables.

### `config.json` format (exact keys)

```json
{
  "meeting_title": "Meridian fortnightly sync",
  "duration_min": 45,
  "target_date": "2026-05-11",
  "window_start": "18:00",
  "window_end": "23:00",
  "attendees": ["ada", "bo", "cy", "dee"],
  "late_hour": 22,
  "buffer_after_late_min": 30,
  "step_min": 15
}
```

- `duration_min` — meeting length in minutes.
- `target_date` — `YYYY-MM-DD`. Availability and the scheduled meeting are all
  expressed in **UTC** on that same date.
- `window_start`, `window_end` — search-window bounds as `HH:MM` clock times on
  `target_date`. The window end may reach `"24:00"` (meaning midnight at the
  start of the next day). Times later than the candidate meeting must fit
  *inside* the window: a candidate that starts so late that `start +
  duration_min` would pass `window_end` is not valid.
- `attendees` — the ordered list of attendee ids.
- `late_hour` — a threshold clock hour (`22` = 22:00 UTC).
- `buffer_after_late_min` — the recovery buffer, in minutes.
- `step_min` — candidate-start scan step in minutes.

### `<attendee>.avail` format

One occupied interval per line:

```
2026-05-11T18:00:00Z|2026-05-11T18:45:00Z
2026-05-11T19:30:00Z|2026-05-11T20:00:00Z
```

- Each line is `START|END` where both are `YYYY-MM-DDTHH:MM:SSZ` (UTC).
- A file may be **empty** (those lines -> that attendee has no meetings in the
  window and is free throughout it).
- A configured attendee whose `.avail` file is **missing** is treated as fully
  available.
- **Malformed lines** — blank lines, lines without a `|`, zero-length or
  reversed intervals (`END <= START`) — are ignored.

## The recovery-buffer rule (most important)

Any occupied interval $(S, E)$ that **ends at or after `late_hour` on
`target_date`** (i.e. `E >= target_date+late_hour:00`) is a **late meeting**.
After a late meeting the attendee(s) need a recovery buffer, so that interval's
effective footprint is extended to run until `E + buffer_after_late_min`.

**You must not place the candidate meeting at a time that overlaps an *effective*
occupied footprint** (ordinary intervals count as before; late intervals count
until their buffer has fully elapsed). Overlap uses the half-open convention: a
candidate `[c, c+duration)` conflicts with `[s, e)` when `c < e and
c+duration > s`. A candidate starting exactly at an interval end (or an interval
ending exactly at a candidate start, including right after the buffer) does
*not* conflict — the gap is one-sided.

The earliest valid slot is the smallest candidate start `c` with
`c >= window_start`, stepping by `step_min`, `c + duration <= window_end`, and
`c` not conflict with any effective occupied interval. The buffer must therefore
shift the answer: A naive scheduler that ignores the buffer will pick a start
inside the recovery interval and is **wrong**.

## What `/app/schedule.py` must do

Running `python3 /app/schedule.py` (no arguments) must:

1. Read `/app/availability/config.json` and each attendee's `.avail` file,
2. compute the earliest buffer-aware conflict-free slot described above,
3. write `/app/earliest_slot.ics` — a valid, fold-correct iCalendar
   `VCALENDAR` containing exactly one `VEVENT` with:
   - `DTSTART` / `DTEND` in **UTC** (`YYYYMMDDTHHMMSSZ`), DTEND = DTSTART +
     duration,
   - `SUMMARY` exactly equal to `config["meeting_title"]`,
   - at least one `ATTENDEE` line per attendee,
   - a `UID`, `DTSTAMP`, and `DESCRIPTION` (any sensible values).
   No DTSTART without `Z`; no physical line longer than 75 octets (fold if
   needed);
4. **discover** the per-person schedule producer under `/app/tools/` (search
   for a file named `person_producer.py`), **read its calling convention from
   its source / its `--help`**, and for **every** attendee in
   `config["attendees"]` run it and save its stdout to exactly
   `/app/personals/<attendee>.txt` (one entry of the per-person snapshot set
   `/app/personals/*.txt`, with exactly one file per attendee);
5. write `/app/summary.txt` containing at least these lines:
   ```
   EARLIEST_SLOT=<YYYYMMDDTHHMMSSZ or "none">
   MEETING_TITLE=<config meeting_title>
   DURATION_MIN=<duration_min>
   OCCUPIED_INTERVALS=<count of parsed occupied intervals>
   LATE_HOUR=<late_hour>
   BUFFER_AFTER_LATE_MIN=<buffer_after_late_min>
   ```
   `EARLIEST_SLOT` is `none` only when no valid slot fits the window.
6. print to stdout a line `EARLIEST_SLOT=<...>` too (the same slot value, or
   `none` when no slot fits).

In items 1–5, wherever a path under `/app` is named (`/app/availability`,
`/app/earliest_slot.ics`, `/app/personals/…`, `/app/summary.txt`), a run with
`--avail` / `--out` substitutes the given directories; `/app/tools` never
moves.

### Discoverability

- The tool is `python3 /app/tools/person_producer.py --person <id>`. Learn
  this from the tool itself (`python3 .../person_producer.py --help` or its
  source). Do **not** hard-code its outputs or its roster — drive it and use
  what it prints.

## Edge cases the hidden verifier probes

- `morning-prime` — a normal morning window with a few scattered one-uppers and
  one attendee whose file is empty; EARLIEST should come from the genuine gap.
- `evening-buffer` — the naive (buffer-less) earliest slot lands inside a
  recovery buffer after a late meeting; the correct answer must be pushed out.
- `edge-resilience` — malformed (zero-length/reversed) lines are skipped,
  overlapping intervals are handled so the union is still correctly
  represented, and a late meeting ending *exactly* at `late_hour` gets its
  buffer + min.
- The verifier re-runs `/app/schedule.py --avail <case dir> --out <scratch dir>`
  on each of these fresh, *read-only* availability sets and checks the
  emitted ICS `DTSTART`/`DTEND`, the stdout `EARLIEST_SLOT` line, the
  per-person files, and that **no input file is modified** (the same
  read-only guarantee as `/app/availability`).

## Constraints

- All paths literals: `/app/availability`, `/app/tools`, `/app/earliest_slot.ics`,
  `/app/personals/<name>.txt`, `/app/summary.txt` (with `--avail`/`--out` the
  availability and output directories are the ones given on the command line,
  as described in the Objective).
- You must not create or write anything under `/tests` (mounted read-only).
- The input availability directory is strictly read-only for your program;
  changing it fails verification.
- Keep the output deterministic (fixed content for DTSTAMP is fine — but the
  compound `DTSTART` / `DTEND` / `SUMMARY` must follow the rule).
- Only the deliverables under `/app` produced by running `/app/schedule.py` are
  graded.