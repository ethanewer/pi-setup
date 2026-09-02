# Mist Buoy tide-gauge archive: build a contract-driven API client

The **Mist Buoy archive** serves tide-gauge data over a small REST API. A
live instance is running at:

```
http://127.0.0.1:8098
```

**The API is not documented anywhere except the service itself**: fetch

```
GET http://127.0.0.1:8098/contract.json
```

and read it. It is the authoritative, complete description of the routes,
methods, query parameters, request/response payload shapes, error codes and
the authentication header the API expects. Do **not** guess routes or
payloads: wrong paths return 404, the retired `/api/v1/...` paths return 410,
and calls missing the required auth header return 403. If the local instance
is not reachable, you can (re)start it yourself with:

```
python3 /app/server.py /app/data/visible.json 8098 &
```

You work only inside `/app`. Do not touch anything outside `/app`.

## Deliverables (both required)

1. `/app/client.py` — a runnable Python program with this interface:

   ```
   python3 /app/client.py <base_url> <output_json>
   ```

   It must fetch and read the contract doc from `<base_url>/contract.json`
   and then follow it to produce the report below. It must work against
   **any** base URL serving this same API — including instances whose
   contract version, archive key, campaign constants (selection status,
   metric, window) and data all differ from the local one. Do not hard-code
   anything you can read from the contract doc or the API responses.

2. `/app/report.json` — the output your program produces when run against
   the local instance:

   ```
   python3 /app/client.py http://127.0.0.1:8098 /app/report.json
   ```

## What the client must do

1. Fetch `/contract.json` and parse it. From the doc, read:
   - the auth header name and value (see the `auth` object),
   - the campaign constants (see the `campaign` object): the `select_status`
     a station must have, the `metric` to report on, and the fixed
     measurement `window` (`from` inclusive / `to` exclusive),
   - the route descriptions (paths, methods, query parameters, payload
     shapes, status codes).
2. Page through **all** stations via the stations listing route, following
   the continuation token each response provides until it is `null`.
3. Select the stations whose `status` equals the campaign's `select_status`.
4. Submit a report job via the reports route with exactly the payload shape
   the contract specifies: the selected station ids, the campaign metric and
   the campaign window. A successful submit returns **202** with a job id.
5. Poll the job resource until its `status` is `done` and take its `result`.
6. Write the output JSON.

## Required output JSON

```json
{
  "contract_version": "<string taken from the contract doc>",
  "stations_total": <int, number of stations fetched across all pages>,
  "stations_selected": <int, number of stations matching select_status>,
  "report": <the job's result object, verbatim>
}
```

## Edge cases the grader probes (hidden instances)

The verifier starts fresh instances of the same service with **different
data files** (and therefore different contract versions, archive keys,
campaign selections, metrics, windows, station counts and readings) and runs
your client against them. Your program must therefore:

- re-read the contract doc on the given base URL for every run (the archive
  key, selection status, metric and window all differ between instances);
- handle listing responses split across many pages (page sizes are small);
- handle an empty selection, and a selection whose report contains **zero
  readings** (the result's `min`/`mean`/`max` are then `null`);
- handle the async job lifecycle (a job is not done on the first poll);
- never require network access beyond `<base_url>` itself (localhost only).

## Constraints

- The verifier runs your client **unchanged** (`python3 /app/client.py`) on
  hidden instances, so no hard-coded versions, keys, station ids, ports
  other than the one passed as `<base_url>`, or result values.
- Do not modify `/app/server.py` or anything under `/app/data/`.
- Python standard library only; no third-party packages.
