# alewife-dune

You are inside a real open-source crypto library tree: **Mbed TLS** (the
`Mbed-TLS/mbedtls` repository), checked out at a pinned commit in `/app/src`
(the working tree starts clean and detached at that commit). The library
builds in place with plain `make`. There is a memory-safety bug in this
tree's handling of ECDSA signature format conversion. Your job is to find
it, fix it in the working tree, and prove the fix with the project's own
test suite. You are deliberately **not** told which function or file to
change: localising the bug is part of the task.

## Environment

- Ubuntu 24.04 base with gcc 13.3, `make`, `perl`, `python3` (with its
  jinja2 support modules) and `git`. `cpus = 1`: one vCPU, use `-j1`.
- **There is no network** in this container. Everything needed is baked in:
  the repository and its `framework` git submodule are fully checked out,
  and the library (`library/`) plus three test suites
  (`test_suite_psa_crypto_util`, `test_suite_psa_crypto`, `test_suite_pk`)
  were already built at image build time at this same commit, so incremental
  rebuilds take seconds, not minutes.
- The repository at `/app/src` is a shallow single-commit clone. Do not
  commit, fetch, or push. Edit the working tree only.
- Read `/app/README-BUILD.md` first: it explains how this project's test
  suites are generated and run.

## The bug (user-visible symptom)

Applications that hand the library's PSA API its ECDSA **signature format
conversions** inputs whose size corresponds to a curve larger than the
largest one this build supports (521-bit) get a hard memory-safety crash
instead of a clean error. Concretely: converting a raw `r||s` signature into
its ASN.1 DER form, or converting a DER signature into raw form, with
coordinate sizes above 66 bytes (for example a 544-bit value, which has
68-byte coordinates) aborts the process mid-call. On this hardened build the
crash is deterministic and looks like:

```
*** buffer overflow detected ***: terminated
```

followed by SIGABRT (the process exits 134). On builds without that
protection, the stack is silently corrupted: the conversion returns a wrong
result or crashes later in unrelated code.

The library's contract is that such oversized input must be rejected
**gracefully** with the documented "output buffer too small" error
(`MBEDTLS_ERR_ASN1_BUF_TOO_SMALL`), and that every conversion at a supported
size keeps working byte-for-byte.

## Required work (in this order)

1. **Write a failing reproduction first.** Extend the project's own test
   data file `tests/suites/test_suite_psa_crypto_util.data` with one new
   case per conversion direction (raw->DER and DER->raw) whose coordinate
   size is beyond the supported maximum (544-bit works, as in the symptom;
   copy the file's existing entry format). Each case supplies the
   `key_bits` argument, a quoted hex input, a quoted hex expected-output
   buffer, and the expected return code `MBEDTLS_ERR_ASN1_BUF_TOO_SMALL`.
   The raw input must be exactly `2 * ceil(key_bits / 8)` bytes and the
   DER->raw case's output buffer must be at least that large too (otherwise
   the error would be legitimate even before your fix, and you would not be
   reproducing this bug). Rebuild the suite with
   `make -C tests test_suite_psa_crypto_util` — the data file is embedded
   into the test binary at build time, so this rebuild is mandatory — then
   run `./tests/test_suite_psa_crypto_util` and **observe the crash
   yourself** before changing any other file.

2. **Fix the tree** so your reproduction passes. Keep the change minimal
   and correct:
   - oversized coordinates must be rejected with
     `MBEDTLS_ERR_ASN1_BUF_TOO_SMALL` **before any copying happens**, in
     both conversion directions;
   - conversions at supported sizes are unchanged byte-for-byte. Beware the
     boundary: 528-bit coordinates (66 bytes) still fit in the library's
     fixed-size internal buffers and must keep converting successfully —
     a fix that rejects anything above 521 bits is over-broad and wrong.

3. **Prove it.** Rebuild and run the suite again: your two new cases must
   now print `PASS` and the run must end with
   `PASSED (N / N tests (0 skipped))`.

4. **Write `/app/summary.md`** (a required deliverable): the user-visible
   symptom, the root cause (where and why the unchecked size overflows a
   fixed-size buffer, in both directions), what you changed, and how you
   verified it (the exact commands and their output).

## Constraints

- Only two tracked files may differ from the pinned commit: the file your
  fix lives in, and `tests/suites/test_suite_psa_crypto_util.data` (your
  reproduction). Every other tracked file must remain byte-identical and no
  new files may appear; the verifier checks byte-for-byte.
- Do not disable or weaken FORTIFY/hardening build flags, do not switch
  compilers, do not touch `mbedtls_config.h`, do not delete or skip any test
  in the suite, do not touch `tests/` machinery other than the data file.
- The deliverable is the tree at `/app/src` plus `/app/summary.md`: after
  your fix the project must rebuild and its own suite must pass. The
  verifier rebuilds everything itself from your tree — pre-built binaries or
  git tricks do not count.

Good luck. The root cause is small and local; reproducing it honestly is
the hard part.