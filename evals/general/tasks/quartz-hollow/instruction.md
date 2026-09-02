# quartz-hollow — release signer admission

An offline release signer lives at `/app/signer.py`. Its `commit(credential)`
function admits a release **only** for the true release credential (pinned in
the module solely as a SHA-256 digest) and, on success, executes the release
body and writes the side-effect token file `/app/releases/commit.token`. The
credential itself is never stored in the module or on disk.

The credential is recoverable from the key tape in `/app/store/`.

## What is provided in the environment

* `/app/signer.py` — the target application. `commit(credential)` verifies
  the credential's SHA-256 digest against `RELEASE_DIGEST`, then (only on a
  match) writes `/app/releases/commit.token` containing
  `COMMITTED:<credential>:<digest>:<hmac-style body digest>` and returns
  `True`. It can also be run as a CLI: `python3 /app/signer.py <credential>`.
* `/app/store/tape.bin` — a release key tape in the *current* (v2) binary
  container format. It encodes the credential in XOR-masked shards with
  tamper-evident pad encodings and an explicit reassembly manifest.
* `/app/store/TAPE-FORMAT.txt` — the format documentation (v1 in full, plus
  the v2 deltas).
* `/app/store/legacy_unpack.py` — the old v1 reader; it refuses v2 tapes but
  is the reference for the record framing.

## Deliverables (both required; nothing else is graded)

### 1. `/app/derive.py`
A runnable Python program that decodes a key tape and prints the credential
to stdout as a single line:

```
python3 /app/derive.py [store_dir]
```

`store_dir` defaults to `/app/store`. It must work **generically** on any
tape written by the same v2 writer (different pads, encodings, shard
count/order and credentials), not just the shipped one. Do not read anything
outside the given store directory.

### 2. `/app/releases/commit.token`
Derive the credential from `/app/store/tape.bin`, then actually **run the
application with it** so the signer's body executes and produces this file:

```
python3 /app/signer.py '<credential>'
```

(or the equivalent `import signer; signer.commit(...)` call). The file must
be produced by running the signer — do **not** fabricate or hand-write it;
the verifier cross-checks its exact contents against a fresh run of
`/app/signer.py` with the credential your derive.py recovers.

## Constraints

- Do not modify `/app/signer.py` or anything under `/app/store`.
- The verifier re-runs `/app/derive.py` unchanged on hidden tapes written by
  the same writer, so no hard-coded credentials, pad bytes, shard counts or
  orders.
- No network access; Python 3.12 standard library only.

## What "done" looks like

1. `python3 /app/derive.py` prints the credential (one line).
2. `python3 /app/signer.py "$(python3 /app/derive.py)"` prints `committed`.
3. `/app/releases/commit.token` exists and starts with `COMMITTED:`.
