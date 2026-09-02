# velvet-atlas — deactivating cancelled attendees at the Vesper Point badge desk

**Vesper Point Forums** runs an attendee registry on a small local service ("badgedesk")
that you administer. A batch of attendees cancelled their registration and must be
**deactivated through the registry API** — while every other attendee stays intact and
able to authenticate at the badge desk. Everything is local (no internet, no credentials);
Python 3.12 with the standard library only. Work in `/app`.

## The environment

- The registry service lives at `/app/badgedesk.py`. It is read-only; do not modify it.
- It keeps its state in `/app/store/attendees.json` (seeded with 8 attendees) and an
  append-only audit trail in `/app/store/audit.ndjson`. Do **not** edit the store files
  directly — every state change must flow through the API (the audit trail is checked).
- Start the service once:

  ```bash
  python3 /app/badgedesk.py --store /app/store --port 8841 &
  ```

  It prints a greeting when ready; give it ~1s, then `GET http://127.0.0.1:8841/health`
  to confirm.

### REST surface (base = `http://127.0.0.1:8841`)

- `GET /api/v1/attendees` → `{"attendees": [{attendee_id, full_name, email, affiliation,
  badge_code}, ...]}`
- `GET /api/v1/attendees/{id}` → the attendee, or `404` if absent.
- `GET /api/v1/attendees/{id}/badge` → `{"attendee_id", "badge_code"}` — the badge-desk
  authentication probe; `404` once the attendee is gone.
- `DELETE /api/v1/attendees/{id}` → deletes exactly that attendee; `200` with
  `{"deleted": "<id>"}` if removed, `404` if it did not exist.

Python's standard library `urllib.request` is fine for talking to it.

## Deliverables (both required)

1. `/app/deactivate.py` — a Python client module exposing reusable functions:

   - `cancel_attendees(base, ids)` — given the service base URL and a list of attendee
     IDs, issues `DELETE /api/v1/attendees/{id}` for exactly the listed IDs (skipping any
     that are already absent) and returns the list of IDs that were actually removed.
   - `list_attendees(base)` — returns the current `attendees` array from
     `GET /api/v1/attendees`.

   The functions must be **generic**: the verifier will call them against a fresh service
   seeded with a **different** roster and a different cancellation list, and expects
   exactly the targeted attendees to disappear while every survivor remains present and
   still authenticates (their `/badge` endpoint keeps returning `200`).

   When run as a script (`python3 /app/deactivate.py`), it must perform the cancellation
   of the IDs in `/app/cancel_list.json` (`{"cancel": [...]}`) against the running service
   and write `/app/remaining.json`.

2. `/app/remaining.json` — the record of the run against the seeded store:

   ```json
   {"removed": ["<id>", ...], "remaining": [ {attendee}, ... ]}
   ```

   where `removed` lists the cancelled IDs that were deleted and `remaining` is the full
   live attendee list afterwards (which must equal the seed minus the cancelled IDs).

## Rules & evaluation

- Work only under `/app`; you may add helper files there.
- Do not modify `/app/badgedesk.py`, anything under `/app/store/`, or
  `/app/cancel_list.json`. Never read or write under `/tests` or `/solution`.
- All deletions must go through the REST API; the audit trail in the store records them,
  and hand-edited state files are treated as not having done the work.
- The verifier re-runs the deliverable functions on fresh emulator instances with hidden
  rosters and hidden cancellation lists, so nothing may be hard-coded to the seed above.
- No network access beyond `127.0.0.1`; standard library only.

## Checklist

1. `/app/deactivate.py` with generic `cancel_attendees` / `list_attendees`.
2. `/app/remaining.json` reflecting exactly the cancelled attendees removed.
