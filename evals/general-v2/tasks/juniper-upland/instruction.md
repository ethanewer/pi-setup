# juniper-upland — scheduling desk for Juniper Upland

The Juniper Upland athletic-training facility shares one coordination desk.
Each workday the desk receives a meeting request plus per-member availability
calendars and must (1) find the **earliest conflict-free slot** for the meeting
and emit a **standards-conformant UTC iCalendar** event for it, (2) honour a
fixed **recovery buffer** around late-day meeting blocks, and (3) capture a
per-member **roster snapshot** using a provided helper script.

You will write **one reusable program** `/app/schedule.py`, run it on the
shipped fixture to produce `/app/earliest_slot.ics`, then collect the roster
snapshots and write `/app/summary.txt`.

## Inputs (in `/app`, do NOT modify any of these)

| path | meaning |
|------|---------|
| `request.json` | the meeting request + the roster snapshot list (JSON) |
| `availability/ada.ics` … `availability/ben.ics` … | one UTC iCalendar file per attendee, each set holding that attendee's busy blocks (`VEVENT`s) |
| `kit/roster_feed.py` | the **provided** per-member snapshot producer (reuse it) |

`request.json` has this shape:

```json
{
  "meeting": {
    "title": "…",                      // summary text for the calendar event
    "attendees": ["ada@…", "…"],       // email addresses of required attendees
    "window_begin": "2026-03-16T08:00:00Z", // UTC ISO-8601
    "window_end":   "2026-03-16T20:00:00Z", // UTC ISO-8601
    "duration_minutes": 60,
    "buffer_minutes": 15,
    "late_hour_utc": 17
  },
  "snapshot_members": ["ada", "ben", "carol", "gwen"]
}
```

Every availability `.ics` is named by the **local part** of an attendee address
(e.g. `ada@…` -> `availability/ada.ics`). Each `VEVENT`'s `DTSTART`/`DTEND` are
UTC (`YYYYMMDDTHHMMSSZ`) and denote one occupied/busy block. A busy interval
covers `[start, end)`.

## The scheduling rule (exact)

1. The meeting of `duration_minutes` must lie **entirely inside**
   `[window_begin, window_end)`.
2. A busy block `[b, e)` from *any* attendee forbids that interval outright —
   the meeting may not overlap any attendee's busy time.
3. A busy block is **late** when the **UTC clock hour of its end** `e` is
   greater than or equal to `late_hour_utc`. For every late block, the forbidden
   block is expanded by `buffer_minutes` on **both sides**, i.e. the forbidden
   interval becomes `[b - buffer_minutes, e + buffer_minutes)`. This models the
   recovery window right after a day's late session and the wind-down right
   before it. Non-late blocks get no expansion.
4. **Earliest** = the smallest feasible slot start; if the desk/late buffer were
   wrong, a slightly earlier (but invalid) start must never be chosen. When no
   slot fits, the desk reports `NONE` (see below) and writes an empty calendar.

Step granularity is **1 minute**; times are compared at whole-minute precision.

## Survey data edge cases you must handle (the grader probes these)

- A member's availability file may be **missing** — that member is treated as
  entirely **free**.
- A `VEVENT` may be **malformed** (e.g. a `DTSTART` with no `DTEND`, or a
  non-UTC/bogus timestamp). Skip that single block; never let one bad block
  take down the whole schedule.
- Every input uses **UTC**. Timestamps that are not UTC `Z` are not valid busy
  blocks.
- `late_hour_utc` comparison is **inclusive** (`end.hour >= late_hour_utc`).
- Availability blocks that fall outside the meeting window's calendar day are
  ignored/evidence-only; the buffer must not bleed across midnight.
- Your program **must not write anything into the input directory** and must
  **not modify** `request.json`, the `availability/*.ics` files, or the helper.
  They are checked by hash after you finish.

## Deliverables

Open `/app` and create:

1. **`/app/schedule.py`** — an executable program:
   ```
   python3 /app/schedule.py <input_dir> <output_dir>
   ```
   - Reads `<input_dir>/request.json` and `<input_dir>/availability/*.ics`.
   - Writes the chosen event to `<output_dir>/earliest_slot.ics` (creating
     `<output_dir>` if necessary) using `<input_dir>` paths ONLY; it may not
     assume the `/app/...` fixed paths — the grader re-runs it on new scenario
     directorys.
   - Prints the chosen start in ISO `YYYY-MM-DDTHH:MM:SSZ` on stdout, or
     `NONE` printed if no slot fits.

2. **`/app/earliest_slot.ics`** — the event your program wrote by running
   `python3 /app/schedule.py /app <output>`. It must be standards-conformant:
   - framed by `BEGIN:VCALENDAR`/`END:VCALENDAR`;
   - contains `VERSION:2.0` and a `PRODID:`;
   - a single `VEVENT` whose `DTSTART` and `DTEND` are **UTC** (`…T…Z`) and
     whose duration equals `duration_minutes`;
   - a `UID`, a `SUMMARY` (equal to the request title), and **one `ATTENDEE`
     line per requested attendee** (`ATTENDEE…:mailto:<email>`).

3. **`/app/personals/*.txt`** — four snapshot files, one per `snapshot_members`
   entry, named exactly `<member>.txt` (e.g. `/app/personals/ada.txt`), each
   holding that member's roster snapshot **byte-for-byte**.

4. **`/app/summary.txt`** — a short text that names the chosen earliest slot
   (the same ISO start as the produced ICS) and lists the four snapshot member
   names (each appears somewhere in the file).

## Discovering the helper (do NOT rewrite it)

A provider utility ships inside the container at **`/app/kit/roster_feed.py`**.
To feed the per-member snapshots the desk reuses this helper rather than
regenerating schedules: treat it as a black box, learn its calling convention
(the program prints a usage hint if you run it wrongly, and its source at the
top explains the contract), and for **each** short `snapshot_members` name
capture its stdout into `/app/personals/<name>.txt`. Run it via
`python3 /app/kit/roster_feed.py <member>` — do not call it with exotic flags
and do not simply copy its source. An unknown member prints an error and
exits non-zero.

## Verification

A grader will, after your working session:
- run `/app/schedule.py` against the visible fixture and against fresh hidden
  scenario directories; open each produced `.ics` with an independent parser
  and check structure, `VEVENT`, UTC stamps, the attendee list, and that
  `DTSTART` equals the earliest start recomputed from the rules above;
- confirm `request.json` and every `availability/*.ics` are byte-for-byte
  untouched;
- replay the provided `/app/kit/roster_feed.py` for each snapshot member and
  compare each stored `/app/personals/<name>.txt` **byte-for-byte** to its
  stdout;
- check `/app/summary.txt` names the same earliest slot and every snapshot member.

Keep all helper code under `/app`; all deliverables must live under `/app`.
Available Python packages include `ics`, `python-dateutil`, and `pandas` (stdlib
datetime/re is sufficient if you prefer).