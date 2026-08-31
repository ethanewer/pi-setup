# Pearl-Cipher — invert the Pearl32 oracle under a strict time budget

The Pearl-Cipher lab ships **Pearl32**, a key-parametrized 30-bit block cipher,
with its authoritative reference implementation at **`/app/cipher.py`** (read
it — it is the exact spec; the verifier checks it stays unmodified).

Your mission: given a key and a ciphertext block (the *target*), recover the
plaintext **preimage** by querying the cipher over the whole 30-bit block
space — under a strict time budget. Pearl32 is a bijection on `[0, 2^30)`, so
exactly one preimage exists.

The catch: a naive per-value implementation (e.g. calling `/app/cipher.py` once
per candidate, or a pure-Python loop over 2^30 values) cannot enumerate the
block space in time. You must reimplement the cipher **in bulk** — vectorized
(with the preinstalled `numpy`) or compiled C — and stream the whole domain
through it until the target matches. The verifier allots **90 seconds per
case** end-to-end.

## Deliverables (both required)

1. **`/app/crack.py`** — a runnable program:
   ```
   python3 /app/crack.py KEY_HEX TARGET_HEX OUT_JSON
   ```
   - `KEY_HEX` is the 32-bit key, 8 hex digits (e.g. `9a3c71f2`); `TARGET_HEX`
     is the 30-bit target block, 8 hex digits.
   - It must find `x` in `[0, 2^30)` with `Pearl32.encrypt(x, K) == TARGET`
     and write `OUT_JSON` as JSON: `{"x": <int>, "y": <int target>}`.
   - It must finish within the time budget for ANY key/target pair in the
     documented domain (the verifier uses keys and targets you have not seen).
   - It must not modify `/app/cipher.py`, `/app/key.txt`, or `/app/target.txt`.

2. **`/app/secret.json`** — the result for the shipped visible case, i.e. the
   output of:
   ```
   python3 /app/crack.py "$(cat /app/key.txt)" "$(cat /app/target.txt)" /app/secret.json
   ```

## Files provided in `/app`

- `/app/cipher.py` — the reference cipher (do not modify).
- `/app/key.txt` — visible-case key, one 8-hex-digit line.
- `/app/target.txt` — visible-case target, one 8-hex-digit line.
- `numpy` is preinstalled; `gcc` is available if you prefer a compiled search.

## What the verifier does

- Checks the three provided files are unmodified.
- Re-runs your `/app/crack.py` on the visible key/target (90 s budget) and
  checks `/app/secret.json` matches the expected preimage.
- Re-runs `/app/crack.py` on **hidden** key/target pairs (different keys,
  90 s budget each) and verifies the recovered `x` against the authoritative
  cipher: `encrypt(x, K) == TARGET` with `0 <= x < 2^30`. JSON output must
  parse to `{"x": int, "y": int}` with `y == TARGET`.
- Over-budget runs (timeout) fail the case. All cases must pass.
