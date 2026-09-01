# Claim the spume-ferry pier pass

A small ticketing kiosk service for the **spume-ferry** is installed at
`/app` (package `ferry_app`). Your job is to exercise its HTTP surface: start
the service, discover the claim route, compute a rendezvous payload exactly as
documented below, POST it, and deliver the returned pier-pass message.

## Starting the service

Run the package as a module from `/app` and keep it running:

```
cd /app && python3 -m ferry_app.app
```

It binds `http://127.0.0.1:8652` (override the port with the `FERRY_PORT`
environment variable). Verify it is up, e.g.:

```
curl -s http://127.0.0.1:8652/api/v1/announce
```

## Deliverables (all under `/app`)

1. `/app/claim_pass.py` — an executable Python script run as
   `python3 /app/claim_pass.py <dock_id>`. Given a single integer dock id it:
   - computes the rendezvous payload with the formula below,
   - POSTs it to the claim route,
   - writes the JSON response body to `/app/claim_receipt.json`,
   - prints the returned `final` pier-pass string to stdout and exits 0.
   If the argument is **not an integer**, or is an integer with **no open
   receipt**, the script MUST exit non-zero, print a clear diagnostic to
   stderr, and MUST NOT print any `pierpass-...` string to stdout. It must
   talk to the live service every run (never hard-code final strings or
   receipts).

2. `/app/final_message.txt` — the `final` pier-pass string your script prints
   for the **default dock id `21`**, as a single line:
   ```
   python3 /app/claim_pass.py 21 > /app/final_message.txt
   ```

3. `/app/claim_receipt.json` — the JSON response body written by
   `/app/claim_pass.py` when run with dock id `21`. It must contain
   `"status": "claimed"`, the `"dock"`, and the `"final"` string.

## Wire contract

- `GET  /api/v1/announce` — liveness probe.
- `GET  /api/v1/routes` — lists the service routes (route discovery).
- `GET  /api/v1/receipts` — lists the dock ids that currently have an open
  receipt.
- `POST /api/v1/claim` — body `{"tide": <12 hex chars>, "slip": <int>}`.
  Returns `200` with `{"status":"claimed","dock":<int>,"final":"pierpass-…"}`
  when the payload matches an open receipt, `400` for a malformed body, and
  `409` when no receipt matches.

## Rendezvous payload formula (for an integer dock id `D`)

```
nonce  = (D*13 + 11) % 1000000
digest = sha256(("spume:%d" % nonce).encode("utf-8")).hexdigest()
tide   = digest[0:12]
slip   = int(digest[0:8], 16) % 9000 + 1000
POST body = {"tide": tide, "slip": slip}
```

The `final` field of a successful claim response is the pier-pass message.

## Edge behaviour the verifier probes

- `python3 /app/claim_pass.py seven` → non-zero exit, diagnostic on stderr,
  no `pierpass-` output.
- `python3 /app/claim_pass.py 999` (no open receipt) → non-zero exit, no
  `pierpass-` output.
- `python3 /app/claim_pass.py 7` (open receipt) → exit 0, prints the correct
  pier-pass string for dock `7`.

Do not modify `/app/ferry_app/`; treat the service as a black box. Create
only your deliverables in `/app`. No network access beyond the local
service; Python standard library only.

When finished, confirm all three deliverables exist and `claim_pass.py`
behaves exactly as contracted.
