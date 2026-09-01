# sable-hook — unseal the deployment vault

You are handed a locked deployment pipeline under `/app`. Nothing in it will
produce output until the vault is genuinely unsealed. You must (A) recover the
access passphrase by reverse-engineering the shipped binary, (B) use the
passphrase with the gatekeeper to obtain the deploy secret it guards, and (C)
run the target application with that derived secret so its body actually
executes and emits its side-effect file. **You may not fabricate the
side-effect file by hand — it can only be produced by a real run of the
application.**

## What is provided in the environment

* `/app/gatekeeper` — a **stripped ELF binary** (the C source is not shipped).
  Invoked as `./gatekeeper <passphrase>` it prints `LOCKED` for anything but
  the true access passphrase. For the correct passphrase it prints
  `GRANTED DEPLOY_SECRET=<secret>`. Internally it compares a rolling
  XOR-obfuscated table of bytes against your input, and decodes the guarded
  deploy secret from a second obfuscated table using a different 4-byte key.
  Tools such as `objdump -d`, `objdump -s -j .rodata`, `strings`, `readelf`
  and `hexdump` are available (install nothing; no network access).
* `/app/vault_service.py` — the target application. Its function
  `open_vault(secret)` executes the vault body (and writes the side-effect
  file `/app/vault_out/unsealed.txt`) **only** when `secret` is the true deploy
  secret; only the SHA-256 digest of that secret is pinned in `VAULT_DIGEST`.
  It also has a CLI: `python3 /app/vault_service.py <secret>`.

## Deliverables (all three required; exact paths)

### 1. `/app/recovered_passphrase.txt`
A plain text file whose trimmed content is the **access passphrase** you
recovered from the binary. The verifier feeds this file's content to a fresh
run of `/app/gatekeeper` and requires the `GRANTED DEPLOY_SECRET=...` line —
so it must be the actual passphrase the binary validates, not a copy of the
deploy secret.

### 2. `/app/unseal.py`
An executable Python script. Running `python3 /app/unseal.py` (with working
directory `/app`) must invoke the target application — e.g. import
`vault_service` and call `open_vault(...)` with the derived deploy secret, or
subprocess `python3 /app/vault_service.py <secret>` — so that the vault body
executes and writes `/app/vault_out/unsealed.txt` as a side effect. Your
script must **not** write that file itself; the verifier detects a fabricated
file (it compares the file the run produces against what the pristine
application produces). It must be self-sufficient: **it must still work when
`/app/recovered_passphrase.txt` has been deleted** (embed whatever it needs).

### 3. `/app/vault_out/unsealed.txt`
The side-effect file produced by actually running the application with the
derived secret (deliverable 2 run at least once).

## Constraints

- Do **not** modify `/app/gatekeeper` or `/app/vault_service.py`. The verifier
  checks that the application is pristine and still rejects wrong secrets, and
  that the gatekeeper still locks wrong passphrases.
- Work under `/app` only. No network access.

## What "done" looks like

1. `/app/gatekeeper "$(cat /app/recovered_passphrase.txt)"` prints
   `GRANTED DEPLOY_SECRET=...`.
2. `python3 /app/unseal.py` (from `/app`) exits 0 and (re)creates
   `/app/vault_out/unsealed.txt` with the application's real output.
3. `python3 /app/vault_service.py wrong-guess` prints `VAULT LOCKED` and
   creates nothing.
