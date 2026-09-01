# glacier-vane — microscope core spectral channel calibration

**Glacier Ridge Microscopy Core** is re-configuring its imaging channels and
needs a reusable calibration client that talks to the facility's local
spectra service. You must author one self-contained Python program under
`/app`, then run it to produce the required output artifact. Everything you
need is already on disk as read-only fixture data; **you must not modify or
delete any file under `/app` that you did not create yourself, and you must
never touch anything under `/tests`.**

## Deliverables (both required)

1. `/app/spectra_client.py` — a runnable Python program with this interface:
   ```
   python3 /app/spectra_client.py <data_dir> <out.json>
   ```
   `<data_dir>` holds a spectral database (see below). The program must start
   the provided localhost API server, query it over HTTP, and write the
   calibration report to `<out.json>`. It must work on **any** data directory
   that follows the documented format, not just the provided one.

2. `/app/spectra_report.json` — the report your program produces when run on
   the provided data:
   ```
   python3 /app/spectra_client.py /app/data /app/spectra_report.json
   ```

## Environment

- Working directory: `/app`. The fixtures are `/app/data/proteins.json` (the
  spectral database consumed by the server), `/app/data/channels.json` (the
  channel specification), and `/app/api_server.py` (a read-only mock API
  server; do not change it). Python 3.12 is available as `python3`.
- There is **no outbound internet**. The only network your client may touch is
  `127.0.0.1` for the server you start yourself.

## The local spectra API

Start it yourself on a free `127.0.0.1` port:

```
python3 /app/api_server.py <data_dir>/proteins.json <port>
```

Then poll `GET http://127.0.0.1:<port>/health` until it returns `200`. The
server exposes:

- `GET /health` → `{"ok": true}`
- `GET /api/spectra?page=<N>&per_page=<M>` → paginated listing
  ```json
  {"page": N, "per_page": M, "total": <total proteins>, "items": [
     {"id": "...", "excitation_nm": 488, "emission_nm": 512, "brightness": 22}, ...]}
  ```
  **The server caps `per_page` at 5** no matter what you ask for, so you must
  page through with `page=1,2,3,...` (use `total` to know when to stop) to see
  every protein.
- `GET /api/spectra?id=<id>` → `{"id","excitation_nm","emission_nm","brightness"}`
  or `404 {"error": ...}` for an unknown id.
- `GET /api/status?id=<id>` → `{"id","status"}` where status is `"active"` or
  `"withdrawn"`, or `404` for an unknown id.

## Channel selection rules

`channels.json` contains an object
`{"channels": [ <channel>, ... ]}` where each channel is:

```json
{"channel": "ch0", "laser_nm": 488, "laser_tolerance_nm": 4,
 "emission_min": 500, "emission_max": 535, "min_brightness": 12}
```

For each channel, a protein is a **candidate** if and only if **all** hold:

1. its status (via `/api/status`) is `active` — withdrawn proteins must be
   excluded even when their spectra match;
2. `|excitation_nm - laser_nm| <= laser_tolerance_nm` (inclusive);
3. `emission_min <= emission_nm <= emission_max` (inclusive);
4. `brightness >= min_brightness` (inclusive).

Among the candidates for a channel, choose the winner as follows:

- highest `brightness` wins;
- if two or more candidates tie on brightness, the lexicographically smallest
  `id` wins.

The data are always seeded so every channel has at least one candidate.

## Required output JSON

Write `<out.json>` exactly in this schema:

```json
{
  "channels": {
    "<channel name>": {
      "protein_id": "...",
      "excitation_nm": 0,
      "emission_nm": 0,
      "brightness": 0
    }
  },
  "unassigned_channels": []
}
```

- The `channels` object must have one entry per channel from `channels.json`,
  and the inner payload must equal the chosen protein's `/api/spectra` payload
  exactly (the four keys `id`, `excitation_nm`, `emission_nm`, `brightness` —
  note the payload key is `id`, not `protein_id`).
- `unassigned_channels` is a sorted list of channel names that had no
  candidate; the provided inputs guarantee this is always `[]`.
- Exit status `0` on success. Never read `/tests`.

## Constraints

- The verifier re-runs your program **unchanged** on hidden data directories
  (fresh protein catalogs with different ids, spectra, brightness values and
  withdrawn flags, plus fresh channel specs), so do not hardcode the visible
  data. A withdrawn protein that spectrally out-shines every other candidate
  for a channel is present in the visible data on purpose: it must lose to the
  active winner.
- Standard library only (`urllib.request`, `subprocess`, `socket`, `json`, ...).
- Do not modify `/app/data/proteins.json`, `/app/data/channels.json`, or
  `/app/api_server.py`.
