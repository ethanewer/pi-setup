# Calendar slot selection for a project sync

Access `/app/schedule.ics` — a small iCalendar (ICS) file describing events on a fixed day.
You must choose **one** contiguous 60-minute meeting slot for the "Project sync" meeting, find
a room for it, and produce both an invite ICS file and a structured decision report.

## What is in `/app/schedule.ics`

The ICS uses UTC, floating/absolute times, and each `VEVENT` has `DTSTART`, `DTEND`,
`SUMMARY`, `LOCATION`. There are two kinds of events:

- **Room blocks**: events whose `LOCATION` is `Boardroom` or `Meeting Room A`. They mark
  times when that room is unavailable.
- **Attendee busy blocks**: events that carry an `ATTENDEE` property
  (`alice@acme`, `bob@acme`, `carol@acme`). These mark when that person is busy.

## People and rooms

Invited attendees (must all be free during the meeting): **Alice**, **Bob**, **Carol**.

Rooms and capacities:
- `Boardroom` — capacity 12
- `Meeting Room A` — capacity 4

The meeting needs capacity for at least 3 people.

## Hard constraints (all must hold)

- The meeting is on **2024-11-18**, 60 minutes long, start and end **on a 15-minute
  boundary** (start time in the set of 00/15/30/45 minute marks) within **09:00–17:00 UTC**.
- The chosen 15.00 slot must not overlap any attendee busy block (all of Alice/Bob/Carol free
  for the whole window).
- The chosen room must not be blocked during the window.
- Room capacity must be ≥ 3 (number of attendees).

## Soft preferences (to pick the best when more than one slot is feasible)

1. Prefer the room whose capacity is the **smallest that still fits** the attendees
   (minimize wasted seats among feasible rooms).
2. If two identical-feasibility slots remain, pick the earliest start time.

Apply preferences only **after** hard constraints are satisfied.

## Expected artifacts

1. `/app/invite.ics` — a valid iCalendar file containing exactly one `VEVENT` with:
   - `SUMMARY:Project sync`
   - `DTSTART` and `DTEND` in the chosen 60-minute window (UTC, same basic format as the
     source file, e.g. `20241118T160000Z`)
   - `LOCATION:<chosen room>`
   - `ORGANIZER:mailto:coordinator@acme`
   - `ATTENDEE:mailto:alice@acme`, `bob@acme`, `carol@acme`
2. `/app/decision.json` — a JSON object:
   ```json
   {
     "meeting": "Project sync",
     "date": "2024-11-18",
     "start_utc": "2024-11-18T16:00:00Z",
     "end_utc": "2024-11-18T17:00:00Z",
     "room": "Meeting Room A",
     "satisfied_hard_constraints": true,
     "why_this_slot": "short description of how hard filters + soft preference led here",
     "verified_against_schedule": true
   }
   ```
   The `start_utc`/`room` must match what is in `/app/invite.ics`.

You must actually derive the slot from the calendar data, not guess. Before finishing, confirm
that the chosen window does not overlap any block in `schedule.ics` / one of the three people
free and the room free.