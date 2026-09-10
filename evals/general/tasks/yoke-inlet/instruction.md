# yoke-inlet: TLS reverse-proxy front door with canary traffic split and failover

You are the platform engineer for the "yoke inlet" front door. The environment
ships two application servers; your job is to configure and operate a reverse
proxy in front of them: terminate TLS at the proxy, split traffic between the
two upstreams as a **weighted canary**, fail requests over to the surviving
upstream when one of them dies, and record every proxied request in a **custom
access-log format**. All three will be exercised for real by the verifier.

## Environment

Installed: nginx 1.24, openssl 3, curl, python3, plus small process-control
utilities (pkill/pgrep, fuser). No pip packages are provided and none may be
installed at run time (no network in the trial container).

### The shipped upstream application

`/app/upstreams/app_server.py` is a Python 3 stdlib HTTP server (do not modify
anything under `/app/upstreams/`). You run one instance per upstream:

```
python3 /app/upstreams/app_server.py --name <name> --port <port>
```

- Every GET path other than the two below answers HTTP 200 with a JSON identity
  block:
  `{"server": "<name>", "port": <port>, "path": "<path>", "query": "<query>", "banner": "yoke"}`
- `/healthz` answers HTTP 200 with `{"status": "ok", "server": ..., "port": ..., "banner": "yoke"}`.
- The instance started with `--name canary` is **the canary**; the instance
  started with `--name stable` is **the stable upstream**. Both serve identical
  content, so only the JSON `server` field reveals which one handled a request.

## Fixed topology (this is your contract)

| role | listen address |
|---|---|
| canary upstream | `127.0.0.1:8123` |
| stable upstream | `127.0.0.1:8124` |
| reverse proxy (TLS) | `127.0.0.1:8443` |

The proxy terminates TLS and re-connects to the two upstreams over plain HTTP.
The upstreams must be reachable **through the proxy** at those fixed addresses;
the verifier never talks to the upstreams directly.

## Deliverables

1. **`/app/start.sh`** — a self-contained, idempotent startup script for the
   whole stack (see the startup contract below).
2. **`/app/nginx.conf`** — your nginx configuration, loaded by `/app/start.sh`
   with `nginx -c /app/nginx.conf`.
3. **`/app/tls/ca.crt`** — a fresh self-signed CA certificate you generate with
   openssl.

All of these must exist after your work and survive re-runs of `/app/start.sh`.

## TLS

- Generate a fresh self-signed CA and sign a server certificate with it for the
  proxy. Keys, server certificates, serial files and any other TLS material go
  under `/app/tls/`.
- The verifier connects to `https://127.0.0.1:8443` and validates the chain
  using **only** `/app/tls/ca.crt` — certificate trust *and* hostname
  verification on, no `-k`-style shortcuts. Make that work: the certificate you
  sign must be valid for connections made to `127.0.0.1`.

## Traffic split (the canary)

Requests through the front door must reach **both** upstreams, with the canary
receiving the larger share. Measured over a batch of 300 sequential requests,
the fraction served by the **canary** must be **between 60% and 72%**. The
split must hold for every proxied path, and every request in the batch must
succeed.

## Failover

While both upstreams are up, every request succeeds. If one upstream becomes
unreachable, the front door must detect the outage on its own and keep serving
**every** request from the surviving upstream — no manual intervention, no
reload. The verifier kills one upstream at a time and then issues a fresh batch
of requests; every one must still succeed and be answered by the **surviving**
upstream. That means a request that lands on a dead peer must be retried on a
live one instead of being answered with an error. This must work in **both
directions**: canary killed → stable takes over; stable killed → canary takes
over.

## Access log

- The proxy writes an access log with a **custom named `log_format`** to
  `/app/logs/access.log`.
- Every request produces exactly one line that is the following pipe (`|`)
  delimited record — these 9 fields, in this order, nothing before or after:

```
YOKE|<iso8601 timestamp>|<request line>|<status>|<bytes sent>|<upstream addr(s)>|<upstream response time>|<request time>|<user agent>
```

| # | example |
|---|---|
| 1 | `YOKE` (literal) |
| 2 | `2026-07-18T09:41:02+00:00` (ISO-8601) |
| 3 | `GET /mortar HTTP/1.1` |
| 4 | `200` |
| 5 | `71` (non-negative integer) |
| 6 | `127.0.0.1:8123` (two addresses joined with `, ` when one request retried) |
| 7 | `0.004` (decimal seconds; same joining rule) |
| 8 | `0.006` (decimal seconds) |
| 9 | verbatim `User-Agent` request header value |

Exactly nine pipe-separated fields. The verifier parses this file on the pipe
character for routes it has never sent before, so the format must be exactly
this and nothing else.

## The startup contract (`/app/start.sh`)

- **Idempotent**: safe to run any number of times; from any prior state it must
  end with a working stack (stopping whatever the stack itself previously left
  running is fine).
- Starts both upstream apps **and** nginx, and does not return until the front
  door actually answers.
- Works as the current user **without root privileges**: it may create and write
  anything under `/app` (except `/app/upstreams/`), but must not need sudo,
  must not use privileged ports, and must not bind beyond loopback. Runtime
  state (pid files, temp dirs, logs) stays under `/app/logs/` and `/app/run/`.
- The verifier behaves like this on every run: stop whatever is listening on
  ports 8123, 8124 and 8443, run `/app/start.sh`, then poll
  `https://127.0.0.1:8443/healthz` until it answers 200. If the stack can
  already serve correctly, `/app/start.sh` may exit 0 immediately instead of
  restarting.

## What the verifier checks (three independent runs)

The verifier repeats the following with three different route sets; two of them
are hidden and contain paths you have never seen, so nothing may be special-
cased per path (today's visible routes are `/mortar` and `/trestle`):

1. Start the stack fresh, fetch `/healthz` **and** a content route over
   `https://127.0.0.1:8443` using `/app/tls/ca.crt` (verification fully on),
   check response bodies are the upstream identity JSON.
2. Issue 300 sequential requests spread over the case's routes and assert the
   canary's share is in the 60–72% band.
3. Parse `/app/logs/access.log` and assert the exact 9-field YOKE record exists
   for every route of the case.
4. Kill one upstream (a different one per case), issue 30 fresh requests and
   assert every response is HTTP 200 and served by the surviving upstream.
5. Assert the failover batch also appears in the same log format.

## Constraints

- Work only under `/app`. Never touch `/tests/`, `/solution/`, or system
  configuration outside `/app` (no `/etc/nginx` edits, no init scripts).
- Do not modify `/app/upstreams/`.
- No processes other than your own stack may listen on 8123, 8124 or 8443.
- If anything is ambiguous, prefer the behavior the verifier checks over any
  other reading of this text. Check `/app/logs/error.log` when the stack fails
  to come up — it usually says why.