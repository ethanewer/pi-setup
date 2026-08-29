# calm-jetty — driving the Halcyon municipal cloud

**Halcyon Transit** runs its operational analytics on a small private cloud that
you administer. The cloud is emulated locally (no internet, no credentials) and
speaks a small REST API. Your job is to perform four operations against it and
leave behind the working client code plus the resulting artifacts. Everything
must be done over the real HTTP API — the harness will verify that the work was
carried out through the API (there is an append-only audit trail), so do **not**
hand-edit the provider's state files.

## The environment

- A local cloud emulator lives at `/app/cloudsvc.py`. It is read-only; do not
  modify it.
- It keeps its state in JSON files under `/app/store/` that it reads and writes
  itself. Do **not** edit those files directly.
- Start the emulator once (it serves all four services on one port):

  ```bash
  cd /app
  python3 /app/cloudsvc.py --store /app/store --port 8791 &
  ```

  It prints a greeting when it is ready; give it ~1s, then call
  `http://127.0.0.1:8791/health` to confirm.

### REST surface (base = `http://127.0.0.1:8791`)

Blob storage:

- `PUT /blob/v2/buckets/{bucket}/policy` — body: a bucket-policy JSON document.
- `GET /blob/v2/buckets/{bucket}/access?object={key}` — returns
  `{"bucket","object","allowed","reason"}` where `allowed` is `true` iff the
  bucket's current policy grants **anonymous public** `s3:GetObject`.

Sheets:

- `POST /sheets/v1` — body `{"name": "..."}` → `201` `{"spreadsheet_id","name"}`.
- `POST /sheets/v1/{spreadsheet_id}/sheets` — body `{"title": "..."}` → `201`
  `{"sheet_id","title"}` (nests the worksheet inside that spreadsheet).
- `GET /sheets/v1` — full list of spreadsheets.
- `GET /sheets/v1/{spreadsheet_id}` and
  `GET /sheets/v1/{spreadsheet_id}/sheets/{sheet_id}` — presence/title lookups.

Identity management:
- `GET /identity/v2/accounts` → `{"accounts":[{user_id,full_name,email}]}`.
- `GET /identity/v2/accounts/{user_id}` → the account, or `404` if absent.
- `DELETE /identity/v2/accounts/{user_id}` → deletes exactly that account;
  `200` if removed, `404` if it did not exist.

Python's standard library `urllib.request` is fine for talking to it; `requests`
is also pre-installed.

## Deliverables

Create all of the following under `/app`.

### 1. `/app/bucket_policy.json` — make a bucket publicly readable

The object bucket named **`reports`** exists but is private (its policy is
`null`). Write a policy document so the bucket becomes **publicly readable**
(public `s3:GetObject`), and **apply it** to the service with
`PUT /blob/v2/buckets/reports/policy`.

The accepted policy must grant, for the anonymous public principal, an
`Allow` effect for action `s3:GetObject` on resource `arn:aws:s3:::reports/*`.
A minimal accepted document looks like:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::reports/*"
    }
  ]
}
```

`Principal` may be the string `"*"` or `{"AWS":"*"}`; `Action`/`Resource` may be
a string or a list. After applying it, any object in `reports` (e.g.
`2024-boardings.parquet`, `2025-forecast.parquet`) must report
`"allowed": true` through the `/access` endpoint.

### 2. `/app/sheets_client.py` + `/app/sheet_ids.json` — create a spreadsheet and a worksheet

Write a Python client that, using the Sheets REST API:

- creates a spreadsheet named **`quarterly-updates-2025`** via
  `POST /sheets/v1`, and
- creates a worksheet titled **`scorecard-by-stage`** inside it via
  `POST /sheets/v1/{spreadsheet_id}/sheets`.

The client must define reusable functions `create_spreadsheet(base, name)` and
`create_worksheet(base, spreadsheet_id, title)` (returning the JSON bodies from
the API). Nothing may be hard-coded to today's names: the harness will call your
functions against a **fresh** server with **different** spreadsheet and
worksheet names and expect them still to work.

When run (`python3 /app/sheets_client.py`), it must write
`/app/sheet_ids.json` containing the returned identifiers:

```json
{"spreadsheet_id": "<...>", "sheet_id": "<...>"}
```

Both identifiers must be real IDs returned by the API and must resolve to
existing, usable resources.

### 3. `/app/normalize_rpc.py` + `/app/rpc_normalized.json` — normalize RPC responses

A legacy gateway returns verbose, nested "RPC responses". Downstream consumers
require a flat canonical schema. A sample of raw responses is in
`/app/sample_rpc.json` (a JSON list).

Implement a function `normalize_rpc(raws)` that accepts **either one** raw
response dict (returns one flat dict) **or a list** of them (returns a list of
flat dicts, one per entry, in order). Then run it over `/app/sample_rpc.json`
and write the results to `/app/rpc_normalized.json` as `{"cases": [...]}` (one
normalized object per raw entry, in order).

The canonical output has **exactly these keys, in this order**:

```
request_id, account_id, handle, email, region, tier, storage_gb, breach, active
```

Source mapping (all values derived from the raw doc):

| key          | from raw                                        | normalizing rule                                    |
|--------------|-------------------------------------------------|------------------------------------------------------|
| `request_id` | `raw.request_id`                                | string; `""` if absent                                |
| `account_id` | `raw.lookup.account_id`                          | string; `""` if absent (`77420` → `"77420"`)         |
| `handle`     | `raw.lookup.handle`                              | string; `""` if absent (`1337` → `"1337"`)           |
| `email`      | `raw.lookup.contact.email`                      | string, or `null` if absent / blank / not a string    |
| `region`     | `raw.lookup.contact.market`                     | string, or `null`                                    |
| `tier`       | `raw.lookup.entitlement.tier`                  | lowercased, trimmed; or `null`                        |
| `storage_gb` | `raw.lookup.budget.storage_gb`                 | integer, or `null` (accepts numeric strings)          |
| `breach`     | `raw.lookup.budget.breach`                     | integer, or `null` (accepts numeric strings)          |
| `active`     | `raw.lookup.guardrail.aware`                   | the boolean itself, or `null` if not a boolean        |

The normalization must be **robust to malformed input**: any of the nested
sections (`lookup`, `contact`, `entitlement`, `budget`, `guardrail`) may be
missing entirely, individual fields may be missing/`null`/empty, `tier` may
arrive mixed-case with surrounding whitespace, `storage_gb`/`breach` may be
JSON numbers **or numeric strings**, and non-boolean truth values for `aware`
must become `null` (never coerced). `normalize_rpc` must never raise and must
always emit every one of the nine keys.

### 4. `/app/delete_users.py` + `/app/users_remaining.json` — delete specific accounts

The identity store is seeded with the 8 accounts in `/app/accounts_seed.json`.
`/app/delete_targets.json` contains the exact set to remove:
`{"targets": ["u_102", "u_105", "u_107"]}`.

Write a client that deletes **exactly** those three account IDs (via
`DELETE /identity/v2/accounts/{user_id}`) and **leaves every other account
intact** and still queryable.

Expose reusable functions:
- `delete_targets(base, targets)` — deletes exactly the listed IDs, returns the
  list of IDs that were removed.
- `list_accounts(base)` — returns the current `accounts` array.

When run (`python3 /app/delete_users.py`), the client must perform the deletion
of the targeted accounts and write `/app/users_remaining.json`:
```json
{"deleted_targets": ["..."], "accounts_remaining": [ {account}, ... ]}
```
where `accounts_remaining` is the full live list after deletion (which must
equal the seed minus the targets). The client must be generic: the harness will
call `delete_targets(...)`/`list_accounts(...)` with a **different** set of
accounts and target IDs and expect exactly the targeted ones to disappear while
every survivor stays present and returns `200` on `GET`.

## Rules & evaluation

- Work only under `/app`. You **may** add whatever helper files you like there.
- Do not modify `/app/cloudsvc.py`, any file under `/app/store/`, the fixtures
  (`sample_rpc.json`, `accounts_seed.json`, `delete_targets.json`), and never
  read or write under `/tests` or `/solution`.
- All state changes must flow through the REST API (the emulator logs every
  operation; hand-edited state files are treated as not having done the work).
- The verifier will re-run each deliverable — including against **hidden**
  inputs and a provisionable hidden emulator state — so no artifact may be
  hard-coded to the seed data above. Every `deliverables` file must exist.

## Checklist (all under `/app`)

1. `bucket_policy.json` written and applied so `reports` reports public reads.
2. `sheets_client.py` + `sheet_ids.json` (spreadsheet + nested worksheet).
3. `normalize_rpc.py` + `rpc_normalized.json` (flat schema, 9 fixed keys).
4. `delete_users.py` + `users_remaining.json` (only targets gone).