# RelayGrid console — complete an authenticated session

You are building the **official CLI client for the RelayGrid console**, a small
JSON-over-HTTP service with a challenge/response login, an authenticated task
listing, and explicit session termination. Your client must complete a **full
login → work → logout session** and only then write its report artifact.

Everything lives in `/app`. The grader executes your client unchanged against
**fresh origin servers** (different credentials, iteration counts, and task
lists — all following the identical documented protocol), so implement the
protocol generically; never hard-code the reference values. Do not modify
`/app/relayd.py`, `/app/ref_scenario.json`, or `/app/ref_passfile.txt`. Never
read or depend on `/tests` or `/solution`.

## Deliverables (both required)

1. `/app/client.py` — a runnable Python 3 program (standard library only,
   e.g. `urllib.request`, `hashlib`, `json`) with this interface:
   ```
   python3 /app/client.py --origin http://127.0.0.1:<port> \
                          --user <username> --passfile <path> --out <report.json>
   ```
   All four flags are required.

2. `/app/report.json` — the report your client produces **when run against the
   reference origin** (see "Reference run" below). The report must exist only
   as the product of a complete, successful session.

## Protocol

All request and response bodies are JSON. `SHA256_HEX(s)` means the lowercase
hex SHA-256 digest of the UTF-8 bytes of the string `s`.

### 1. `GET /api/challenge`

→ `200 {"challenge": "<32 lowercase hex chars>", "iterations": <int >= 1>}`

The server issues a fresh one-time challenge and tells you the deployment's
digest **iteration count**.

### 2. `POST /api/login`

Request body:
```json
{"user": "<username>", "challenge": "<echoed challenge>", "proof": "<hex>"}
```

The proof is derived from the passphrase (read from `--passfile`, see below)
and the challenge:

```
proof_1 = SHA256_HEX(challenge + ":" + passphrase)
proof_k = SHA256_HEX(proof_{k-1})    for k = 2 .. iterations
proof   = proof_iterations
```

For `iterations = 1` the proof is just `proof_1`. The request must carry the
header `X-Client: grid-cli` (sending it on every login is always correct).

- Success → `200 {"session": "<token>", "user": "<username>"}`. Keep the
  session **token from this JSON response**; the service does not use cookies.
- Wrong user, stale/unknown challenge, wrong proof, or missing `X-Client`
  header → `403` or `400`. **Do not retry**: a failed authentication must
  leave no report artifact.

### 3. `GET /api/tasks`

Must carry the header `Authorization: Bearer <session token>`.

→ `200 {"tasks": [ ... ]}` — the deployment's task list (possibly empty).

Without a valid bearer token → `401`.

### 4. `POST /api/logout`

Must carry the same `Authorization: Bearer <session token>` header. No body
is required.

→ `200 {"logged_out": true}` — the token is invalidated server-side.

## Passfile format

`--passfile` points at a plain-text file whose (first) content line is:
```
passphrase: <secret>
```
Trim whitespace around the value. Do not print the passphrase anywhere.

## Report artifact

Only after logout returns `200 {"logged_out": true}`, write `--out` as JSON
with exactly these keys:
```json
{
  "user": "<username passed via --user>",
  "challenge_used": "<the challenge consumed by the successful login>",
  "session_token": "<token returned by the successful login>",
  "tasks_count": <number of tasks returned by GET /api/tasks>,
  "logged_out": true
}
```

`session_token` must be the token you actually authenticated with, and
`challenge_used` the challenge your proof was built from — the grader checks
both against the origin's own audit log. If any step fails (non-200 response,
unexpected body), exit non-zero and **do not write the report**.

## Reference run (develop against a live origin)

```
python3 /app/relayd.py --config /app/ref_scenario.json --port 20085 --audit /tmp/ref_audit.jsonl &
python3 /app/client.py --origin http://127.0.0.1:20085 \
                       --user grid-user --passfile /app/ref_passfile.txt \
                       --out /app/report.json
```

For the reference origin the passphrase is `lantern-bay-42`, the iteration
count is 2, and `tasks_count` is 4. Use these only to sanity-check your
pipeline; hidden deployments differ in username, passphrase, iteration count
(including 1), task list (including empty), and port.

## Constraints

- Python 3.12 standard library only; no pip packages, no network access beyond
  the origin you are given.
- The client must not modify the scenario config, the server, or the passfile.
- One clean session per invocation: exactly one successful login and one
  logout, and no requests using the token after logout.
