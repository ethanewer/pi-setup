# harbor-loom — structural-genomics sequence fetcher

**Harbor Point Structural Genomics** mirrors a structure database locally and
needs a reusable fetch client that resolves structure identifiers to their
amino-acid sequences. You must author one self-contained Python program under
`/app`, then run it to produce the required output artifact. Everything you
need is already on disk as read-only fixture data; **you must not modify or
delete any file under `/app` that you did not create yourself, and you must
never touch anything under `/tests`.**

## Deliverables (both required)

1. `/app/seqfetch.py` — a runnable Python program with this interface:
   ```
   python3 /app/seqfetch.py <data_dir> <out.json>
   ```
   `<data_dir>` holds a structure database (see below). The program must start
   the provided localhost API server, resolve every requested identifier over
   HTTP, and write the result to `<out.json>`. It must work on **any** data
   directory that follows the documented format, not just the provided one.

2. `/app/sequences_out.json` — the output your program produces when run on
   the provided data:
   ```
   python3 /app/seqfetch.py /app/data /app/sequences_out.json
   ```

## Environment

- Working directory: `/app`. The fixtures are `/app/data/db.json` (the
  structure database consumed by the server), `/app/data/requests.json` (the
  identifier list), and `/app/api_server.py` (a read-only mock API server; do
  not change it). Python 3.12 is available as `python3`.
- There is **no outbound internet**. The only network your client may touch is
  `127.0.0.1` for the server you start yourself.

## The local structure API

Start it yourself on a free `127.0.0.1` port:

```
python3 /app/api_server.py <data_dir>/db.json <port>
```

Then poll `GET http://127.0.0.1:<port>/health` until it returns `200`. The
server exposes:

- `GET /health` → `{"ok": true}`
- `GET /api/entries/<ACCESSION>` → entry metadata:
  ```json
  {"accession": "7QNR", "status": "current" | "obsolete",
   "superseded_by": "8XYZ" | null, "chains": ["A", "B"]}
  ```
  or `404 {"error": ...}` for an unknown accession.
- `GET /api/sequences/<ACCESSION>/<CHAIN>` →
  - `200` for a **current** entry:
    ```json
    {"accession": "7QNR", "chain": "A",
     "lines": ["MKVL...up to 80 chars...", "..."],
     "sha256": "<hex digest of the joined sequence>"}
    ```
    The sequence is returned **wrapped at 80 columns** in `lines`; the true
    sequence is the concatenation of the lines with no separator.
  - `410 {"error": "obsolete", "superseded_by": "<accession>"}` for an
    **obsolete** entry — the sequence must then be fetched from the
    superseding accession instead.
  - `404` for an unknown accession or chain.

Accessions and chains are stored uppercase in the database; the server
uppercases whatever you send, but requested identifiers may be written in any
case.

## Resolution rules

`requests.json` is an object `{"requests": ["<id>", ...]}`. Each identifier
has the form `<ACCESSION>.<CHAIN>` (e.g. `7QNR.A`). For each identifier:

1. Split it into accession and chain at the **last** dot, normalize both to
   uppercase, then resolve the entry: while `/api/entries/<acc>` reports
   `status: "obsolete"`, follow `superseded_by` (chains of supersessions may
   be longer than one hop; they always terminate at a current entry).
2. Fetch `/api/sequences/<acc>/<chain>` from the current entry, join the
   `lines` into a single sequence string, and verify that
   `sha256(sequence) == sha256` from the payload.
3. Record the sequence **keyed by the original identifier exactly as it
   appears in `requests.json`** (original casing preserved, not normalized).

## Required output JSON

Write `<out.json>` exactly in this schema:

```json
{
  "sequences": { "<original id>": "<joined amino-acid sequence>", ... },
  "checksum_failures": []
}
```

- One `sequences` entry per requested identifier, keyed by the original id
  string; the value is the exact sequence the API returned (you must never
  alter, re-wrap, or edit it).
- `checksum_failures` is a sorted list of original ids whose sha256 did not
  match; the provided inputs guarantee this is always `[]`.
- Exit status `0` on success. Never read `/tests`.

## Constraints

- The verifier re-runs your program **unchanged** on hidden data directories
  (fresh databases with different accessions, chain sets, supersession chains
  up to three hops, and mixed-case identifiers), so do not hardcode the
  visible data.
- Standard library only (`urllib.request`, `subprocess`, `socket`, `json`,
  `hashlib`, ...).
- Do not modify `/app/data/db.json`, `/app/data/requests.json`, or
  `/app/api_server.py`.
