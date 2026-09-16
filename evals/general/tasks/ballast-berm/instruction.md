# PSA decryption of short messages spuriously fails in CCM\* no-tag mode

## Situation

`/app/src` is a shallow, pinned clone of the mbedtls repository
(`https://github.com/Mbed-TLS/mbedtls`) at upstream commit
`dd48f0f23f8b5189031d6f3ac519b2b6113bd9e7`, checked out in detached HEAD.
Its `framework` submodule is checked out, and the library plus the PSA crypto
test suite have already been compiled, so everything works entirely offline.
There is **no network** at trial time: `git fetch`, `curl` and any other
network use will fail.

The project builds with plain `make` (GNU make, gcc). The libraries are
already built; rebuilding after a source edit is an incremental compile:

```
cd /app/src && make -j1 lib
cd /app/src && make -C tests -j1 test_suite_psa_crypto
cd /app/src && ./tests/test_suite_psa_crypto
```

`make` will only recompile what your edit touches, so each cycle is seconds,
not minutes. The test suite binary is the harness that decides whether the
bug is present: it prints one line per case and a summary line at the end.

## The bug

The PSA crypto API exposes a one-shot decryption call
`psa_cipher_decrypt()` for symmetric ciphers, including the mode "CCM\*"
(CCM star) in its **no-tag** form: AES with an unauthenticated, pure-CTR
style keystream derived from a nonce, with all of the nonce and ciphertext
concatenated into one input buffer, and no separate authentication tag.

In this checkout, that call rejects short but perfectly valid messages.
When the nonce-plus-ciphertext input is shorter than one AES block
(16 bytes), the call fails with `PSA_ERROR_INVALID_ARGUMENT` (-135), even
though CCM\* needs the input to be only as long as the nonce it is given.
A ciphertext of 2 bytes, or even 0 bytes, after the nonce is rejected,
while the identical message a couple of bytes longer decrypts fine — so
saved or relayed packets of a few bytes are spuriously dropped.

The suite already contains the regression cases for this behaviour. Run the
prebuilt binary:

```
cd /app/src && ./tests/test_suite_psa_crypto
```

You will see exactly two cases fail, e.g.:

```
PSA symmetric decrypt: CCM*-no-tag, NIST DVPT AES-128 #15, 0 bytes  FAILED
PSA symmetric decrypt: CCM*-no-tag, NIST DVPT AES-128 #15, 2 bytes  FAILED
FAILED (1947 / 1949 tests (309 skipped))
```

That is the bug: those messages are valid and their decryption must succeed.
The same suite also contains a case asserting that an input shorter than
the nonce is correctly rejected — that behaviour must be preserved.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. `psa_cipher_decrypt` accepts and correctly decrypts valid CCM\* no-tag
   messages whose nonce-plus-ciphertext input is shorter than one AES block
   (including a zero-byte ciphertext after the nonce); the two failing
   regression cases above pass, and the whole suite reports
   `PASSED (1949 / 1949 tests (309 skipped))`;
2. decryption of genuinely malformed messages (input shorter than the nonce
   itself) is still rejected with `PSA_ERROR_INVALID_ARGUMENT` exactly as
   before, and every other cipher (CBC, ECB, CTR, stream ciphers, ...) keeps
   its current length checks and passes the whole suite.

The tests in the tree are the spec: take them as authoritative. Drive your
work with the suite — the full run takes only a few seconds once built.

## Constraints

- Network is unavailable; everything needed is installed and prebuilt.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, or
  change build files, and do not add or rename files inside the repository.
- The regression-test data under `tests/suites/` is part of the image the
  way the fix intended it; the verifier checks that it stays byte-identical.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit; the only differences from it are
   the minimal source change that fixes the bug plus the regression-test
   data the image already carries, and nothing new inside the repository.
2. The project's own test suite — built from your repaired tree — passes
   end to end: `PASSED (1949 / 1949 tests (309 skipped))`, which includes
   the upstream regression cases for this bug.
3. Hidden cases: decryption of additional short CCM\* no-tag messages with
   keys and message lengths the regression cases do not use (including
   AES-256 and messages of 1, 4, 5, 8, 15 and 16 ciphertext bytes) must
   succeed and return the exact plaintext.

Deliverable: the repaired `/app/src` tree.