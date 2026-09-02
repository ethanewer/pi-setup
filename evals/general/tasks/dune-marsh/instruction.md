# LanternGate — enable password-based authentication on the gateway

A **LanternGate API gateway** was deployed with password-based authentication
disabled. The security baseline requires it to be enabled: the gateway must
accept the configured secret (below) and reject everything else. Your job is
to generate a proper password hash for the secret and wire it into the
gateway's auth configuration.

## Provided files under `/app` (do NOT modify `/app/gateway_service.py`)

- `/app/gateway_service.py` — the gateway service (read-only; the verifier
  boots fresh copies of it).
- `/app/gateway/config.json` — the gateway configuration. Auth is currently
  disabled:
  ```json
  "auth": {
    "enabled": false,
    "scheme": "pbkdf2_sha256",
    "iterations": 30000,
    "password_hash": null
  }
  ```

## The configured secret

```
SableKey-68North
```

## Hash scheme (exactly this format)

The `password_hash` value must be the string:

```
pbkdf2_sha256$<iterations>$<salt_hex>$<dk_hex>
```

where:

- `<iterations>` is the **same integer** as the config's `auth.iterations`
  (the gateway derives with the iteration count embedded in the hash);
- `<salt_hex>` is lowercase hex of at least **8 random bytes**;
- `<dk_hex>` is lowercase hex of the 32-byte derived key:
  `dk = PBKDF2-HMAC-SHA256(secret, salt, iterations)`
  (i.e. `hashlib.pbkdf2_hmac("sha256", secret.encode(), salt, iterations)`).

## Deliverables (both required)

1. `/app/enable_auth.sh` — an **executable**, **idempotent** bash script that
   enables password-based authentication for a gateway config:
   ```
   bash /app/enable_auth.sh [CONFIG_PATH]
   ```
   - With no argument it targets `/app/gateway/config.json`.
   - With an argument it targets the given config path (same schema — the
     verifier runs it against fresh configs with **different** `iterations`
     and ports, so never hard-code `30000` or the visible path).
   - It must set `auth.enabled` to `true` and `auth.password_hash` to a valid
     hash of the secret in the exact scheme above, leaving every other config
     key untouched, and exit `0`. It may regenerate the salt on re-runs; the
     result must always verify. Diagnostics go to stderr; printing the hash to
     stdout is allowed but optional.
   - Use only standard tools available in the image (`python3` is available).

2. `/app/auth_hash.txt` — a text file whose single line is the hash you
   installed into `/app/gateway/config.json`. It must verify against the
   secret with the visible config's `auth.iterations`.

## Gateway service contract

Start a gateway with:
```
python3 /app/gateway_service.py --config <config.json> --port <port>
```
It serves `GET /api/health` on `127.0.0.1:<port>`:

- when `auth.enabled` is `true` (with a parseable hash): requests **without**
  a valid `Authorization: Bearer <secret>` header get `401`; a request with
  the correct secret gets `200` and a body with `"status": "ok"`;
- when auth is disabled or the hash is missing/garbage, the verifier treats
  the gateway as unprotected — that fails the run.

## Success check (what the grader enforces)

- Both deliverables exist (`enable_auth.sh` is executable) and re-running
  `/app/enable_auth.sh` (no argument) exits `0` and leaves the config valid.
- `/app/gateway/config.json` has `auth.enabled == true` and a `password_hash`
  that: uses the `pbkdf2_sha256` scheme, embeds exactly the config's
  `auth.iterations`, carries a salt of >= 8 bytes, and **verifies** the
  secret `SableKey-68North` (and does **not** verify a wrong secret).
- `/app/auth_hash.txt` verifies the same way.
- A freshly booted gateway on the visible config returns `401` without/with a
  wrong bearer token and `200` with the correct one.
- The same holds for hidden configs (different `iterations`, `enabled` flags,
  and ports) after your script is run on them.

## Constraints

- Work as root. No network beyond `127.0.0.1` loopback.
- Do not modify `/app/gateway_service.py`; do not change the config's schema
  (only flip `auth.enabled`, set `auth.password_hash`, and leave `scheme` and
  `iterations` as they are).
- `/app/enable_auth.sh` must be idempotent: run it twice in a row without
  error, both runs leaving a verifying hash in place.
