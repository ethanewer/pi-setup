# Moorfield structural archive — sequence retrieval by identifier

The **Moorfield structural genomics archive** exposes its entries through a
localhost REST service. You must write a reusable client that, given a list of
structure identifiers, walks the two-stage API (entry metadata, then
per-chain sequences) and records **exactly** the amino-acid sequences the API
returns — any wrong or edited sequence fails equality against the API.

## Environment

- Working directory: `/app`. It contains the read-only fixtures:
  - `/app/structure_server.py` — the local mock archive service (do not
    modify).
  - `/app/db/entries.json` — the archive database it serves.
  - `/app/db/spec.json` — the list of structure identifiers to retrieve.
- Python 3.12 is available as `python3`. There is **no outbound internet**;
  the only network you may touch is `127.0.0.1`.
- **Do not modify or delete any file under `/app` that you did not create, and
  never touch anything under `/tests`.**

## Deliverables (both required)

1. `/app/struct_client.py` — a runnable Python program:
   ```
   python3 /app/struct_client.py <data_dir> <out.json>
   ```
   `<data_dir>` contains `entries.json` and `spec.json` (same formats as
   `/app/db`). It must work on **any** archive/spec conforming to the contract
   below, not just the provided ones.

2. `/app/struct_report.json` — the report your program produces on the
   provided data:
   ```
   python3 /app/struct_client.py /app/db /app/struct_report.json
   ```

## The structure-database API

`/app/structure_server.py` is started as
`python3 /app/structure_server.py <data_dir>/entries.json <port>`. Your client
must:

1. Pick a **free TCP port** on `127.0.0.1`, start the server with
   `subprocess`, and poll `GET http://127.0.0.1:<port>/health` until it
   returns HTTP 200. Tear the server process down before exiting.
2. For **each** identifier in `spec.json`'s `"entry_ids"` (processed in the
   given order), fetch
   `GET /api/entry/<entry_id>` →
   `{"entry_id": "...", "title": "...", "chains": [{"chain_id": "...",
   "length": <int>}, ...]}`.
   This is **metadata only** — it contains no sequences.
3. For every chain listed in that metadata (in the order returned), fetch
   `GET /api/sequence/<entry_id>/<chain_id>` →
   `{"entry_id": "...", "chain_id": "...", "sequence": "..."}` and record the
   returned amino-acid sequence **verbatim**: no truncation, no upper/lower
   re-mapping, no edits of any kind. Unknown entry or chain ids return HTTP
   404 `{"error": ...}`; every id the grader gives you resolves.

## Output format

Write `<out.json>` as exactly this JSON object (no extra keys):

```json
{
  "entries": {
    "<entry_id>": { "<chain_id>": "<amino-acid sequence>", ... },
    ...
  },
  "total_chains":  <int>,
  "total_residues": <int>
}
```

- `entries` has one key per requested entry id, in `spec.json` order, holding
  one key per chain of that entry with the API-returned sequence.
- `total_chains` is the number of (entry, chain) pairs retrieved.
- `total_residues` is the sum of the lengths of all retrieved sequences.
- Exit status `0` on success. Never read `/tests`.

You may use `urllib.request`, `subprocess`, `socket`, and the standard
library. Do not hardcode the visible entry ids, chain ids, or sequences — the
grader re-runs your client on fresh hidden archives.
