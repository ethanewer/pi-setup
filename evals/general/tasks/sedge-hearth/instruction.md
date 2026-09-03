# Sedge Hearth — token-based auth service

The Meridian Harbor intranet runs an internal auth microservice called
**Onyx Gate**. It issues HMAC-signed JWT-style tokens (with claims, expiry,
rotation and a revocation blacklist) over loopback HTTP. Your job: implement
the service as the single deliverable

```
/app/token_service.py
```

## What is already in the container (do not modify these)

- `/app/lib/httpkit.py` — a read-only minimal loopback HTTP framework stub
  (stdlib `http.server` based). It handles socket plumbing: path routing,
  request parsing, JSON response encoding and error helpers. See its module
  docstring for the API (`Request`, `Response`, `HttpError`, `error`,
  `serve`). The verifier byte-compares this file against a pristine copy.
- `/app/config.json` — the service configuration (secret, issuer, lifetimes,
  clock skew, user table). Read it at startup. The verifier byte-compares it
  against a pristine copy too.
- `/app/state/` — directory where the revocation blacklist must persist.

Both fixtures are self-contained; Python 3.12 stdlib is everything you need.

## Deliverable

`/app/token_service.py` — a self-contained Python service. Started as

```
python3 /app/token_service.py
```

it reads `/app/config.json` at startup, binds `config["host"]:config["port"]`
(loopback only), and serves the documented API forever. Use the shipped
framework stub (import `sys.path.insert(0, "/app/lib")` then
`from httpkit import ...`) — do not write your own server plumbing. No
outbound network of any kind is allowed.

## Config schema

```json
{
  "host": "127.0.0.1",
  "port": 8711,
  "secret": "some non-empty string",
  "issuer": "onyx-gate",
  "clock_skew_sec": 2,
  "lifetimes": {"access_sec": 300, "refresh_sec": 3600},
  "users": { "alice": {"password": "...", "display": "..."} }
}
```

Every lifetime is a positive integer, `clock_skew_sec` a non-negative
integer, `secret` a non-empty string, `users` a non-empty object mapping user
name → `{"password": str, "display": str}`. Everything below must be derived
from this file at startup — a secret, issuer, user, lifetime, or port
hardcoded in your code will fail the hidden re-runs (the grader replaces
`/app/config.json` with other configurations and restarts your service).

## Token format (exact — the grader recomputes every byte)

Tokens are JWT-shaped strings: three unpadded base64url segments joined with
`.` — `header.payload.signature` — where base64url is RFC 4648 §5 with the
padding omitted.

- **header segment** = base64url of the UTF-8 bytes of the exact string
  `{"alg":"HS256","typ":"JWT"}` (compact JSON, those keys in that order).
- **payload segment** = base64url of compact JSON (no whitespace) with keys
  in the exact order `sub`, `iss`, `iat`, `exp`, `jti`, `typ`.
- **signature segment** = base64url of `HMAC-SHA256(message,
  key=config["secret"])` where `message` is the ASCII bytes of
  `header_segment + "." + payload_segment`.

The full token string is exactly
`header_segment + "." + payload_segment + "." + signature_segment`.

Claim meanings: `sub` = user name (string), `iss` = `config["issuer"]`,
`iat`/`exp` = integer epoch seconds, `jti` = token id (rule below),
`typ` = `"access"` or `"refresh"`.

## jti generation rule

`jti = "<nonce>-<seq:08x>"` where:

- `<nonce>` — 8 lowercase hex characters, generated fresh at process start
  (tokens minted by different process runs never share a nonce);
- `<seq>` — a per-process counter of **minted tokens**: 0 for the first
  token a process mints, incremented by exactly 1 for every token minted
  afterwards, access and refresh alike (the second token of the first login
  is `...-00000001`, and so on).

## Server time & clock tolerance

- Every request may carry the header `X-Onyx-Now` with an integer
  epoch-seconds value. If present, that value **is** the server's "now" for
  that request: it becomes the `iat` of freshly minted tokens and it is what
  all acceptance windows are checked against. If absent, use the wall clock.
  If present but not an integer ≥ 0, respond `400 bad_request`.
- With tolerance `T = config["clock_skew_sec"]`, a presented token is
  accepted only if `iat <= now + T` **and** `exp >= now - T`.

## Endpoints

| Method | Path | Request | Success (HTTP 200) |
|---|---|---|---|
| POST | `/login` | `{"user": str, "password": str}` | `{"access_token": ..., "refresh_token": ..., "token_type": "bearer", "access_expires_in": <access_sec>, "refresh_expires_in": <refresh_sec>}` — mints an access token then a refresh token for that user, both at `iat = now`, `exp = now +` respective lifetime |
| POST | `/refresh` | `{"refresh_token": str}` | same shape as login; carries `sub` over from the old token; the old refresh token is blacklisted (reason `"rotated"`) **before** the new pair is minted |
| POST | `/logout` | `{"access_token": str}` | `{"ok": true}`; the presented access token is blacklisted (reason `"logout"`) |
| GET | `/me` | header `Authorization: Bearer <access token>` | the six claims: `{"sub", "iss", "iat", "exp", "jti", "typ"}` of the presented token |
| GET | `/health` | — | `{"status": "ok"}` (no authentication) |

`/me` and `/logout` require `typ == "access"`; `/refresh` requires
`typ == "refresh"`. The `Authorization` scheme is `Bearer` (case-insensitive;
single space before the token). Rotation invalidates only the presented
refresh token — the previously issued access token keeps working until it
expires.

## Error contract (exact order matters)

Every error is `{"error": {"code": "...", "message": "..."}}`. A presented
token is validated in this order, returning the first failure:

1. token missing / not 3 segments / undecodable base64url / header or payload
   not a JSON object → `401 invalid_token`
2. header is not exactly `{"alg":"HS256","typ":"JWT"}` → `401 invalid_token`
3. any required claim (`sub`, `iss`, `iat`, `exp`, `jti`, `typ`) missing or
   of the wrong type (`sub`/`iss`/`jti`/`typ` strings, `iat`/`exp` integers)
   → `401 invalid_token`
4. HMAC signature does not match → `401 invalid_token`
5. `iss` != `config["issuer"]` → `401 invalid_token`
6. `typ` not allowed on this endpoint → `401 invalid_token`
7. `jti` present in the revocation blacklist → `401 token_revoked`
8. `iat > now + T` → `401 token_not_yet_valid`
9. `exp < now - T` → `401 token_expired`

Other errors: malformed JSON body, missing required field, or a field of the
wrong type → `400 bad_request`; wrong user or password on `/login` →
`401 invalid_credentials`; correct method is required (`POST` on
`/login`/`/refresh`/`/logout`, `GET` on `/me`/`/health`) → `405
method_not_allowed`; unknown path → `404 not_found`.

## Blacklist persistence

- The revocation blacklist lives at `/app/state/blacklist.json` with the
  exact shape `{"version": 1, "entries": {"<jti>": {"reason": "logout" |
  "rotated"}}}`.
- Written atomically (temp file + rename) on every mutation, guarded by a
  lock for thread safety. Loaded at startup: missing file → start with an
  empty blacklist; file present but malformed → refuse to start (non-zero
  exit).
- `/refresh` and `/logout` are the only mutators. Revoked tokens stay
  rejected after a process restart (the blacklist check runs before the
  clock checks, so a revoked-but-expired token still answers
  `token_revoked`).

## Constraints

- Python 3 stdlib only; loopback network only (`127.0.0.1`); no runtime
  network at all beyond that.
- Do not modify `/app/config.json`, `/app/lib/httpkit.py` (both byte-checked
  by the verifier against pristine copies).
- The only file you create is the deliverable `/app/token_service.py`.

## How the grader probes it

The grader kills any leftover processes, then starts its own instance of
`python3 /app/token_service.py` and:

1. checks `/health`, then logs a user in and **recomputes the whole token
   string** (header, claim set, HMAC signature, jti counter) from the config
   — minted tokens must match the recomputation byte-for-byte;
2. drives `/me` flows, refresh rotation (old refresh replay → `token_revoked`,
   old access still valid), logout (double logout → `token_revoked`);
3. inspects `/app/state/blacklist.json` (exact entry set and reasons);
4. restarts the process mid-test and checks blacklist persistence and that
   valid unexpired tokens keep working; the per-process jti counter restarts
   with a fresh nonce;
5. crafts its own tokens with the config secret: valid, expired
   (`exp = now - T - 1`), boundary-valid (`exp = now - T`), future-iat
   (`iat = now + T + 1`), boundary-valid (`iat = now + T`), tampered payload,
   wrong key, wrong issuer, missing claim, wrong `typ`, and malformed
   shapes — each must produce exactly the documented answer;
6. exercises the `/login`/`/refresh`/`/logout` error matrix (bad credentials,
   missing fields, bad types, broken JSON, wrong methods, unknown paths).
7. Hidden generalization: the same battery is re-run against several other
   configurations (different secrets, lifetimes, clock skew, users, ports)
   written to `/app/config.json` one at a time, so nothing about the shipped
   config may be hardcoded.

A quick smoke check you can run yourself after starting the service:

```
curl -s -X POST http://127.0.0.1:8711/login -d '{"user":"alice","password":"orbit-sunrise"}'
curl -s http://127.0.0.1:8711/me -H "Authorization: Bearer $ACCESS"
curl -s -X POST http://127.0.0.1:8711/logout -d "{\"access_token\":\"$ACCESS\"}"
```