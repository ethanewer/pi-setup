# cypress-lantern operator handbook

## Service

Base URL: `http://127.0.0.1:8917` (override with `LANTERN_PORT`).
Registered beacon ids (deterministic registry):

```
delta-7  orin-4  kestrel-12  mirth-3  quillon-9
```

## Routes

| Route | Method | Request | Success | Failure |
|---|---|---|---|---|
| `/api/announce` | GET | — | `{"service","status","beacons"}` | — |
| `/api/beacon/<beacon_id>/challenge` | GET | — | `{"beacon","challenge","turn"}` | 404 unknown beacon |
| `/api/beacon/<beacon_id>/light` | POST | `{"turn","key"}` JSON | `{"status":"lit","beacon","final"}` | 403 wrong turn/key, 400 malformed body |

## Derivation formulas

For a beacon id `B`:

```
challenge = sha256("waxis:" + B)               -> take first 24 hex chars
turn      = sha256("rotor:" + challenge)       -> take first 8 hex chars
key       = sha256("filament:" + turn)         -> take first 16 hex chars
```

All digests are lowercase hexadecimal. All string concatenations are over
UTF-8 bytes. The `challenge` route already returns the beacon's `challenge`
and its matching `turn`; the light route validates both the `turn` and the
`key` derived from that turn.

The `final` field of a successful `light` response has the form
`lamplit-<8 hex chars>` and is the final signal message for that beacon.

## Default beacon

`delta-7` is the default beacon used for the standing final-message record.
