# Skiff landing toll gateway: enable password-based authentication

The **Skiff landing toll gateway** is deployed at `/app/gateway.py` but its
password-based authentication is **disabled** and its only account entry is a
locked placeholder, so nobody can get past the toll. Your job is to provision a
real password hash for the configured secret and switch password
authentication on. The verifier will (a) run your hash generator on **fresh
hidden secrets**, (b) re-run your provisioning script from scratch, and (c)
start the gateway itself and probe it over HTTP.

## The configured secret

The toll operator's login secret (password) is:

```
TideRope-31Quay
```

The account is **`harbormaster`**, and the hash scheme is **sha512-crypt**
(`$6$...` — the standard `crypt` SHA-512 scheme, e.g. what `openssl passwd -6`
or `crypt.mksalt(crypt.METHOD_SHA512)` produces).

## Deliverables (all three required)

1. `/app/hashgen.py` — a runnable Python 3 program (standard library only):
   ```
   python3 /app/hashgen.py <secret> <out_json>
   ```
   It generates a **fresh random salt** and writes a JSON file to
   `<out_json>` (overwriting it) of exactly this shape, with `indent=2` and a
   trailing newline:
   ```json
   {
     "algo": "sha512_crypt",
     "hash": "$6$<salt>$<digest>"
   }
   ```
   The `hash` must verify: `crypt.crypt(<secret>, hash) == hash`. It must be a
   real sha512-crypt string starting with `$6$`, never the plaintext secret,
   never a locked marker (`!` or `*`).

2. `/app/provision.sh` — an **executable**, **idempotent** bash script that
   enables password-based authentication end to end:
   - generates a sha512-crypt hash of the secret `TideRope-31Quay` (you may
     call your own `/app/hashgen.py`, or use any other local method), and
   - writes `/app/credentials.json` in the exact schema the gateway expects:
     ```json
     {
       "enabled": true,
       "users": {
         "harbormaster": {
           "algo": "sha512_crypt",
           "hash": "$6$...$..."
         }
       }
     }
     ```
     with `"enabled"` set to `true` and the `harbormaster` entry carrying a
     valid, unlocked hash of the secret (a real crypt-verifiable hash must be
     present; `crypt.crypt("TideRope-31Quay", hash) == hash` must hold).
   - Re-running it must succeed again (exit 0) and leave
     `/app/credentials.json` valid. It must not start any server, must not
     touch `/app/gateway.py`, and must not use the network.

3. `/app/credentials.json` — the provisioned credentials file in the state
   after you have run `/app/provision.sh` yourself. The gateway reads this
   file at startup; the verifier starts the gateway against it.

## How the gateway decides

- `GET /health` always returns 200.
- `GET /toll?gate=X` requires HTTP **Basic** auth:
  - if `enabled` is not `true` → `403`;
  - unknown user, wrong password, locked/placeholder hash (`!`, `*`), wrong
    `algo`, or a hash that does not crypt-verify → `401`;
  - valid credentials → `200 {"status": "ok", "user": ..., "gate": ...}`.

Hash verification is performed with the standard `crypt` module
(`crypt.crypt(secret, stored_hash) == stored_hash`), so any correct
sha512-crypt hash of the secret is accepted regardless of its salt.

## Constraints

- Work as root. Standard library only for the Python deliverable; no network
  at any point.
- Do **not** modify `/app/gateway.py` (its integrity is checked) — you enable
  auth purely through `/app/credentials.json`.
- `provision.sh` must not leave any server process running; the verifier
  launches `/app/gateway.py` itself.
- Do not read or modify `/tests` or any verifier data.

## Hints on what hidden cases probe

- Your `/app/hashgen.py` is run on **different secrets** (not just the visible
  one): every emitted hash must crypt-verify against the secret it was given.
- `provision.sh` is executed **again** by the verifier; it must remain
  idempotent (exit 0, credentials still valid).
- The gateway must reject a wrong password and an unknown user with `401`
  while accepting `harbormaster` / `TideRope-31Quay` with `200`.
