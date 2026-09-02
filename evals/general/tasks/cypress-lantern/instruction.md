# Light the cypress-lantern beacons

A small beacon-registry wire service called **cypress-lantern** runs inside this
container. To light a beacon you must fetch its challenge, derive a key from
that challenge using the documented formula, and deliver the computed payload
to the beacon's `light` route. The service then returns the final signal
message.

## Environment

- The service package lives at `/app/lantern_service`. Start it and keep it
  running:
  ```
  cd /app && python3 -m lantern_service.app
  ```
  It binds `http://127.0.0.1:8917` (override with the `LANTERN_PORT` env var).
- `/app/HANDBOOK.md` is the authoritative operator reference for the wire
  contract and the derivation formulas. Python 3.12 is available as
  `python3`.

## Deliverables (both required)

1. `/app/light_beacon.py` — a runnable Python script (standard library only)
   invoked as:
   ```
   python3 /app/light_beacon.py <beacon_id>
   ```
   For a registered beacon id it must, by itself: GET the beacon's challenge
   from the service, derive the payload per the handbook formulas, POST the
   computed payload to the beacon's light route, print the returned `final`
   string on stdout, and exit 0. It must perform the real HTTP round trips —
   do not hard-code final messages.

2. `/app/final_message.txt` — the output of lighting the **default beacon
   `delta-7`**:
   ```
   python3 /app/light_beacon.py delta-7 > /app/final_message.txt
   ```
   The file must contain exactly the final signal line for that beacon.

## Wire contract (from `/app/HANDBOOK.md`)

- `GET /api/announce` — service banner.
- `GET /api/beacon/<beacon_id>/challenge` — returns
  `{"beacon", "challenge", "turn"}` for a registered beacon; **404** for an
  unknown beacon.
- `POST /api/beacon/<beacon_id>/light` with a JSON body
  `{"turn": "<turn>", "key": "<key>"}` — returns
  `{"status": "lit", "final": "..."}` when the payload matches, **403** when
  the turn or key is wrong, **400** for a malformed body.

## Behaviour the grader probes with hidden cases

- The script is re-run against **other registered beacon ids** (listed in the
  handbook) and must light each one, printing its exact final message.
- The script may be run with an **unregistered beacon id**. It must then exit
  with a non-zero status, print a diagnostic to stderr, and print **no**
  `lamplit-...` string on stdout.
- A missing argument must likewise exit non-zero without printing any
  `lamplit-...` string.

## Constraints

- Standard library only in `/app/light_beacon.py` (`urllib.request` is fine);
  no third-party HTTP client is installed beyond the service's own needs.
- Do not modify `/app/lantern_service/` or `/app/HANDBOOK.md`.
- No network access beyond the local service at `http://127.0.0.1:8917`.
