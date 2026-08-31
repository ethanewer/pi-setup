# Basalt Tide — recover the harbor cipher key under a strict budget

The **Basalt Tide** gateway encrypts its telemetry frames with a local cipher
oracle. The algorithm is public; the **16-bit seed** ("key") is not. Your job:
recover the live key by querying the oracle with **chosen plaintexts**, using
a bounded number of queries and a strictly bounded wall-clock time, and report
the recovered key material.

You are in `/app`. Do **not** modify `/app/cipher_service.py` or
`/app/.cipher_seed`.

## The cipher (public algorithm, secret 16-bit seed)

`/app/cipher_service.py` implements it exactly as documented in its source:

- The S-box `S` is `range(256)` shuffled by a backwards Fisher-Yates driven by
  a 16-bit xorshift generator (`x ^= x<<7; x ^= x>>9; x ^= x<<8`, all mod
  `2^16`) seeded with the secret seed.
- A secret position mask `M[j] = S[200+j]` for `j = 0..3`.
- Encryption of a plaintext buffer `p` (1..512 bytes):
  `c[i] = S[p[i]] XOR M[i mod 4]`.

The oracle only ever shows you ciphertext — never the seed.

## Oracle interfaces

- Library: `import cipher_service; eng = cipher_service.Engine();
  eng.query("<hex>")` (visible seed file).
- CLI: `python3 /app/cipher_service.py <hex-plaintext>`.
- Daemon (what the grader uses): `python3 /app/cipher_service.py --serve
  [--port 46071]` — line protocol on `127.0.0.1:<port>`: send a hex plaintext
  line, get a hex ciphertext line. **For the grader run the daemon is started
  with an ephemeral secret** (different from the visible seed file) before
  your program runs; your program must recover the *live* daemon's key.

## Deliverables (both required)

1. `/app/recover.py` — executable Python program, no arguments. It connects
   to the running oracle daemon on `127.0.0.1:46071`, performs its chosen-
   plaintext recovery, and writes `/app/recovery.json`.

2. `/app/recovery.json` — produced by running `python3 /app/recover.py`
   against the locally started daemon (visible seed):

   ```json
   {
     "task": "basalt-tide",
     "seed": "3c7a",
     "sbox": "<512 lowercase hex chars, the recovered S-box>",
     "queries": 2,
     "elapsed_ms": 1200,
     "ok": true
   }
   ```

   - `seed`: the recovered 16-bit seed as exactly 4 lowercase hex digits.
   - `sbox`: the 256 recovered S-box bytes in order, lowercase hex.
   - `queries`: how many oracle queries your program made (must be >= 1 and
     truthful; the daemon counts them independently).
   - `elapsed_ms`: your program's own wall time in milliseconds.
   - `ok`: true iff you verified the recovery end to end.

## Hard budgets (the grader enforces both)

- **At most 64 oracle queries** per run — the daemon logs every query and the
  grader counts the log.
- **At most 60 seconds wall time** per `recover.py` run.

A search that constructs and checks every candidate key without pruning will
not converge inside the budget — structure your search so wrong candidates
are rejected early, and derive what you can from chosen plaintexts instead of
guessing.

## How the grader runs it

For each case (the visible seed and 3 hidden seeds), the grader:

1. kills any stale daemons and clears the query log;
2. starts a fresh `cipher_service.py --serve` daemon whose secret comes from
   an **ephemeral keyfile** (deleted by the daemon at startup — it is not on
   disk afterwards and not in any file you can read);
3. runs `python3 /app/recover.py` once, timing it;
4. reads `/app/recovery.json` and requires:
   - `seed` equals the case's secret seed (4 lowercase hex digits),
   - `sbox` equals the true S-box for that seed (hex, 512 chars),
   - the daemon's query count for the run is `<= 64` and `queries >= 1`,
   - wall time `<= 60` seconds, `ok` is true, all keys present.

Pass requires every case to hold. Note the daemon's seed is therefore NOT in
`/app/.cipher_seed` during grading — only genuine chosen-plaintext recovery
works.

## Constraints

- Offline, single container, standard library only.
- Your program must work for **any** 16-bit seed, including degenerate edge
  values; never hard-code a key.
