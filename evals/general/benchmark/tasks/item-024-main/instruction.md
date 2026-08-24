# Recover the hidden key of a FEAL-like oracle and decrypt a sealed challenge

## Context

`/app/candle` is a small **encryption oracle**: a 16-bit block cipher with a
FEAL-like Feistel round function (addition/XOR/rotate + an 8-bit substitution).
A secret 16-bit key is compiled into the binary; it is **not** printed anywhere
and is **not** recoverable from the static files you can read — it is injected
at build time.

`/app/candle.c` documents the round function and the oracle's command line
surface, but does **not** contain the deployed key value. Your job: recover
that key from the oracle's observable behavior using chosen/known-plaintext
probes, then decrypt a sealed challenge.

## The oracle interface

Run it as a subprocess; each command prints exactly one line to stdout:

- `candle enc <hex2>` — encrypt the 16-bit plaintext given as 1–4 hex digits
  (e.g. `candle enc 00`). Prints the 4-digit ciphertext as uppercase hex.
- `candle challenge` — prints the encryption of a hidden challenge plaintext
  (an uppercase-hex4 word). The plaintext itself is unknown to you.

The round function (from `candle.c`) is 6 Feistel rounds over two 8-bit halves:

```
subkey(r) = ( (KEY + 17*r) & 0xFF ) XOR ( KEY >> 8 )
S(x)      = (7*x + 3) & 0xFF
forward:  L = P>>8;  R = P & 0xFF
          for r in 0..5:
              f = S( R ^ subkey(r) )
              (L, R) = (R, ( (L ^ f) & 0xFF ))
          C = (L<<8)|R
```

## Your task

1. **Probe the oracle** (controlled experiments) — request encryptions for a
   handful of chosen/known plaintexts (e.g. `00`, `01`, `80`, `ff`) and record
   the (plaintext → ciphertext) pairs.
2. **Recover the key** — write a script (Python is fine) that searches the
   16-bit keyspace (65536 candidates) for the key whose forward encryption
   matches all your observed pairs. Validate the recovered key against a
   **fresh** probe you did not use during the search.
3. **Read the challenge** — run `candle challenge` and record its ciphertext.
4. **Decrypt the challenge** — implement the Feistel **inverse** and decrypt
   the challenge ciphertext under the recovered key.
5. **Report** — write `/app/found/solution.json`:

   ```json
   {
     "key":   "<recovered key, 4 uppercase hex digits>",
     "plain": "<recovered challenge plaintext, 4 uppercase hex digits>"
   }
   ```

   Both strings are plain hex **without** a `0x` prefix.

## Success criteria

- `/app/found/solution.json` exists and is valid JSON.
- The recovered `key` reproduces the oracle's `enc` output for **several**
  distinct plaintexts (verify by re-encrypting).
- The recovered `plain` actually decrypts the challenge ciphertext under the
  recovered key (i.e. `candle challenge`'s output, decrypted, equals `plain`).