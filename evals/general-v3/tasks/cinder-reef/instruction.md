# Ember Biosciences FRET pair selection

You are working for **Ember Biosciences**, which is building a fluorescence
resonance energy transfer (FRET) reporter. You must write a client that talks
to the company's **fluorescent-protein spectra API** (a localhost service) and
select the donor and acceptor proteins whose spectra satisfy a FRET design
spec. Choosing a protein whose spectra do not match the spec fails the build,
so the selection must follow the rules below exactly.

## Environment

- Working directory: `/app`. It contains the read-only fixtures:
  - `/app/spectra_server.py` — a local mock of the spectra API (do not modify).
  - `/app/db/api.json` — the fluorescent-protein database it serves.
  - `/app/db/spec.json` — the FRET design spec.
- Python 3.12 is available as `python3`. There is **no outbound internet**;
  the only network you may touch is `127.0.0.1`.
- **Do not modify or delete any file under `/app` that you did not create, and
  never touch anything under `/tests`.**

## Deliverables (both required)

1. `/app/fret_client.py` — a runnable Python program:
   ```
   python3 /app/fret_client.py <data_dir> <out.json>
   ```
   `<data_dir>` contains `api.json` and `spec.json` (same formats as
   `/app/db`). It must work on **any** database/spec conforming to the
   contract below, not just the provided ones.

2. `/app/fret_report.json` — the report your program produces on the provided
   data:
   ```
   python3 /app/fret_client.py /app/db /app/fret_report.json
   ```

## The spectra API

`/app/spectra_server.py` is started as
`python3 /app/spectra_server.py <data_dir>/api.json <port>`. Your client must:

1. Pick a **free TCP port** on `127.0.0.1`, start the server with
   `subprocess`, and poll `GET http://127.0.0.1:<port>/health` until it
   returns HTTP 200. Tear the server process down before exiting.
2. `GET /api/proteins` → `{"proteins": [{"id": "..."}, ...]}` — every protein
   id in the database (retired ones included).
3. `GET /api/spectra?id=<id>` →
   `{"id": "...", "excitation_nm": <int>, "emission_nm": <int>}`.
   Returns HTTP 404 `{"error": ...}` for unknown ids **and for retired
   proteins** (records with `"retired": true` appear in `/api/proteins` but
   404 on `/api/spectra`). **Skip any id whose spectra query 404s.**

## Selection rules

`spec.json` has the form:

```json
{
  "donor":    {"emission_min": <int>, "emission_max": <int>},
  "acceptor": {"excitation_min": <int>, "excitation_max": <int>},
  "max_gap_nm": <int>
}
```

- **Donor**: the unique protein (after skipping 404s) whose `emission_nm` lies
  within `[emission_min, emission_max]` **inclusive**.
- **Acceptor**: the unique protein whose `excitation_nm` lies within
  `[excitation_min, excitation_max]` **inclusive** AND whose spectral gap
  satisfies `0 <= gap_nm <= max_gap_nm`, where
  `gap_nm = donor.emission_nm - acceptor.excitation_nm`.
- Every database/spec pair you will be graded on is seeded so that **exactly
  one** donor and **exactly one** acceptor satisfy all rules. Bounds are
  inclusive; treat the rules exactly as stated — a protein that fits the
  acceptor band but violates the gap constraint (negative gap or gap above
  `max_gap_nm`) must be rejected.

## Output format

Write `<out.json>` as exactly this JSON object (no extra keys):

```json
{
  "donor":    {"id": "...", "excitation_nm": <int>, "emission_nm": <int>},
  "acceptor": {"id": "...", "excitation_nm": <int>, "emission_nm": <int>},
  "gap_nm":   <int>
}
```

- `donor` and `acceptor` must equal the `/api/spectra` payloads of the chosen
  proteins **exactly** (the three keys, values unchanged — no re-rounding, no
  edits). A report built from any other source or with edited spectra fails.
- `gap_nm` is the integer gap between the chosen pair:
  `donor.emission_nm - acceptor.excitation_nm`.
- Exit status `0` on success. Never read `/tests`.

You may use `urllib.request`, `subprocess`, `socket`, and the standard
library. Do not hardcode the visible protein ids, wavelengths, or bands — the
grader re-runs your client on fresh hidden databases.
