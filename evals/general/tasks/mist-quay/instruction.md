# MistQuay tide-relay provisioning

The **MistQuay tide-relay** service at `/app/service/server.py` (a small
Python HTTP fixture — do **not** modify anything under `/app/service/`)
currently runs with password authentication **disabled**. Your job is to
provision password-based access by writing two idempotent provisioning
scripts. The verifier will re-run your scripts and then probe the live
service over HTTP — including **users you have never seen** — so the scripts
must be general and obey the exact contract below.

## Deliverables (both required)

1. `/app/configure.sh` — an **executable**, **idempotent** (re-runnable,
   exit 0 every time) bash script that:
   - enables password-based authentication by setting `enabled = true` under
     the `[auth]` section of `/app/service/config.ini`, and
   - registers the operator account **`marlow`** with password
     **`MistQuay#Runnel-52`** (by calling your `/app/adduser.sh`, below, or
     equivalently).

2. `/app/adduser.sh` — an **executable** bash script with the interface:
   ```
   /app/adduser.sh <user> <password>
   ```
   It creates (or updates, preserving position-independent correctness for
   all other users) the entry for `<user>` in the service's credential file
   `/app/service/users.htpasswd`:
   - file format: one `user:hash` line per account, `#` comments and blank
     lines ignored by the service;
   - the hash **must be a SHA-512 crypt hash** (a `$6$` hash as produced by
     `crypt.crypt(pw, crypt.mksalt(crypt.METHOD_SHA512))`) — any other
     scheme will be rejected;
   - the plaintext password must **never** appear in the file;
   - re-running with the same `<user>` must update that user's entry in
     place (no duplicate lines for the same user) and must not disturb
     entries for other users;
   - the script must exit 0 on success.

Run `/app/configure.sh` yourself at least once so the deployed state is
active (auth enabled, `marlow` registered). The verifier re-runs it and then
checks behaviour, so leaving it unrun fails.

## How the service authenticates

- When `[auth] enabled = false`: every GET returns `200` with body
  `auth-disabled` — this is the broken state you must fix.
- When enabled: a GET without credentials, or with a user not in
  `users.htpasswd`, or with a wrong password, returns `401`; a GET with
  correct HTTP Basic credentials returns `200` with body `cove-ok`.

## What the verifier checks

- Both deliverables exist and are executable; `/app/service/server.py` and
  the rest of `/app/service/` are **unmodified** (any tampering fails).
- `/app/configure.sh` is re-run from the deployed state: exit 0, no errors,
  and the checks below still pass afterwards (idempotence).
- `config.ini` has `[auth] enabled = true` (guarded parse).
- `users.htpasswd` contains a single `marlow:` line whose hash verifies
  against `MistQuay#Runnel-52` via `crypt` and starts with `$6$`; the
  plaintext secret appears nowhere in the file.
- Live HTTP probes against the running service: no credentials → `401`;
  wrong password for `marlow` → `401`; correct secret → `200 cove-ok`.
- **Hidden accounts**: the verifier calls your `/app/adduser.sh` with fresh
  `<user> <password>` pairs you have not seen (including passwords with
  punctuation), then probes the live service for each: correct password →
  `200`, wrong password → `401`, entry format `$6$`, no duplicate lines, and
  `marlow`'s entry still intact and working.

## Constraints

- Work as root. No systemd, no external network.
- Do not modify `/app/service/` (server.py, config.ini structure beyond the
  `enabled` flip done by your script), `/tests`, or verifier data.
- Both scripts must be idempotent: running them twice in a row is a no-error
  no-regression operation.
