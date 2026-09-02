# Depot operations — complete a login and logout session

You are automating the **Depot Operations** control plane. A local HTTP origin
implements a challenge-response login protocol; your client must complete a
full session — authenticate, read the authenticated panel, and cleanly log
out — and save a report of the session.

Everything you produce lives in `/app`. The grader later **executes your
client** against *fresh* origins (different deployments: different hash
algorithms, cookie names, and header requirements), so write it generically
against the documented protocol — never hard-code to the reference config.

Read-only fixtures under `/app` (do NOT modify):
* `/app/origin.py` — the local origin service.
* `/app/config.json` — the reference deployment configuration.

## Deliverables (both required)

1. `/app/solve.py` — an executable Python 3 client. Standard library only
   (`urllib`, `hashlib`, `json`, `http.cookiejar`). No pip packages.
2. `/app/answer.json` — the session report produced by **running** `solve.py`
   against the live reference origin (see below).

## Client CLI

```
python3 /app/solve.py --origin http://127.0.0.1:<port> \
                      --username <user> --password <pass> \
                      --out <report_path>
```

`--origin`, `--username`, `--password`, and `--out` are all required. The
report is written to the `--out` path. On any authentication failure the
client must exit non-zero and write no report.

## Origin protocol

All request/response bodies are JSON unless stated otherwise. Origins listen
on `127.0.0.1:<port>`.

### 1. `GET /challenge`
Returns `200` `{"nonce": "<hex string>", "alg": "<hash name>"}`.

- `alg` is a hashlib hash name: `"sha256"`, `"sha1"`, or `"sha512"`.
  **Read it from the response and dispatch dynamically** — deployments differ.
- The nonce is **single-use**: exactly one `POST /login` may consume it. If a
  login attempt fails, fetch a fresh challenge and retry.

### 2. `POST /login` (`application/x-www-form-urlencoded`)
Form fields:
- `username`, `password` — the given credentials;
- `nonce` — the nonce from step 1;
- `token` — the challenge response: `token = HexDigest(<alg>(nonce + password))`
  computed with the hash named by the challenge response (e.g.
  `hashlib.new(alg, (nonce + password).encode()).hexdigest()`).

Some deployments additionally require the request header
`X-Nonce: <nonce>` (matching the challenge nonce). Sending this header
**unconditionally** is always harmless and is the recommended behavior.

Success → `200` `{"ok": true, "sid": "<session id>"}` and a `Set-Cookie`
issuing a **session cookie** (the cookie name varies per deployment — use a
real cookie jar, e.g. `http.cookiejar`; never hand-roll cookie parsing and
never hard-code the cookie name).
Failure → `401` `{"ok": false}`.

### 3. `GET /panel` (authenticated)
Requires the session cookie issued at login.
- Valid session → `200` `{"username": "<user>", "csrf": "<token>"}`.
- No/invalid session → `401`.

### 4. `POST /logout` (authenticated, CSRF-protected)
Form field `csrf` must equal the `csrf` token returned by `GET /panel`, and
the request must carry the session cookie.
- Success → `200` `{"ok": true, "logged_out": true}`. The server invalidates
  the session: any later `GET /panel` with that session returns `401`.
- Missing/invalid cookie or CSRF → `401`.

## Report JSON

`/app/answer.json` (and every `--out` file) must be exactly:

```json
{
  "username": "<username>",
  "logged_in": true,
  "sid": "<session id from the login response>",
  "csrf": "<csrf token from the panel response>",
  "logged_out": true
}
```

- `logged_in` is `true` only if login, panel, and logout all succeeded.
- `sid` is the session id returned by `POST /login`.
- `csrf` is the token returned by `GET /panel`.

## Reference run (develop against a live origin)

```
python3 /app/origin.py /app/config.json 20115 &
python3 /app/solve.py --origin http://127.0.0.1:20115 \
    --username cartwright --password landing-gear-7 \
    --out /app/answer.json
```

The reference deployment uses `alg` sha256, cookie name `trk`, and no header
requirement. Hidden deployments follow the same documented protocol but vary
the hash algorithm, the cookie name, and/or the `X-Nonce` requirement, and use
different credentials passed on the command line.

## Constraints

- Python 3 standard library only. No network access beyond the given origin
  at verify time.
- Work only under `/app`. Do not modify `/app/origin.py` or
  `/app/config.json`.
- The grader launches its own origins per scenario and runs `/app/solve.py`
  unchanged; it then checks the saved report (including the exact `sid` and
  `csrf` values the origin issued) and that the session was actually
  terminated on the server.
