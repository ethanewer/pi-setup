# capstan-drift

You are working inside a real open-source codebase: **Mbed TLS**
(`Mbed-TLS/mbedtls`), the TLS/crypto library, checked out at a pinned commit
in `/app/src` (detached HEAD, clean working tree, no network). There is a
memory-safety bug in this tree's PKCS#7 support. Your job is to find it, fix
it in the working tree, and prove the fix with the project's own test tooling.
You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

## Environment

- Ubuntu 24.04 with `gcc`, `cmake`, `make`, `perl`, `python3` and git.
  The 4.x build is CMake-only.
- **There is no network** in this container. Everything is already on disk:
  the repository (one shallow pinned commit) with its two submodules
  (`framework` and `tf-psa-crypto`, which itself has a nested `framework`
  submodule) checked out, and a warm `build/` directory produced at
  image-build time (the library and the `test_suite_pkcs7` and
  `test_suite_x509parse` test binaries were compiled there). Any `git`,
  `cmake` or `gcc` command you run completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds (`-j1`; the image was
  pre-built, so incremental rebuilds are quick).
- Do not commit, fetch, reset, or otherwise modify `.git` inside the
  repository or its submodules. Scratch files go in `/tmp`, never in
  `/app/src`.

## The bug (user-visible symptom)

An application that reuses a single PKCS#7 structure object to parse a second
message — the documented pattern of calling the parse API, then the cleanup
API, then the parse API again on the same object — crashes the whole process
with a glibc double-free abort. Concretely, parsing a signed-data message that
has **several signers**, running cleanup, and then parsing a follow-up message
that carries **no signers** leaves a stale internal link in the object;
the very next cleanup attempt hands the same heap block back to the allocator
twice:

```
free(): double free detected in tcache 2
Aborted (core dumped)
```

The library aborts the entire process (`exit 134`) instead of parsing the new
message. The object has to be released and re-parsed across *separate* calls:
a single parse/free pair in isolation is fine; the crash needs the reuse.

## Reproducer

The image ships `/app/repro.c` — a small program (authored for this task)
that parses `framework/data_files/pkcs7_data_multiple_signed.der` (a
signed-data message with several signers), frees the object, then parses
`framework/data_files/pkcs7_data_no_signers.der` (a signed-data message with
no signers) and frees again. Build and run it:

```bash
cd /app/src
gcc -std=c99 -DMBEDTLS_ALLOW_PRIVATE_ACCESS \
    -I include -I tf-psa-crypto/include -I tf-psa-crypto/drivers/builtin/include \
    -I build/tf-psa-crypto/include \
    -o /tmp/repro /app/repro.c \
    build/library/libmbedtls.a build/library/libmbedx509.a \
    build/tf-psa-crypto/core/libtfpsacrypto.a
/tmp/repro framework/data_files/pkcs7_data_multiple_signed.der \
                framework/data_files/pkcs7_data_no_signers.der
echo "exit=$?"
```

On this tree this aborts with `free(): double free detected in tcache 2` and
`exit=134`. Note: if you first try a one-off build, the target
`test_suite_pkcs7` (the project's own test program for this module) already
exists under `build/tests/` and the warm build directory is ready;
`cmake --build build --target test_suite_pkcs7` rebuilds it incrementally.

## Requirements

1. Fix the tree so that the reuse scenario above completes cleanly: the
   second parse of the zero-signer message must succeed and return the
   signed-data result, and subsequent parse/free cycles on the same object
   must not crash or corrupt. The same `repro.c` run must print
   `REUSE-OK` and exit 0.
2. The crash is a symptom of an object-lifecycle defect in the parser's
   cleanup: after one parse the object must be left in a state that is safe
   (a) to parse into again with a completely different message and (b) to
   clean up again. Fix the mechanism, not just this one input sequence —
   the same defect is reachable with other signer counts and other message
   shapes (see Grading). Do not paper over it with global state, a
   singleton, a leak, or a guard that skips work.
3. Everything else must keep working exactly as before: parsing fresh
   objects, messages with any number of signers, messages with certificates,
   rejected messages (malformed input must still fail cleanly with the same
   error codes). The project's own test suites must stay green.
4. Scope: the verifier requires that every tracked file except the **single
   source file where the defect actually lives** be byte-identical to the
   pinned commit; you must identify that file yourself. Do not add, move,
   delete, rename or reformat any file; if you create scratch files to
   investigate, delete them before you finish; make no commits; do not
   modify `tests/`, `include/`, any build script, any configuration file or
   any submodule content. Cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce**: `cmake --build build --target test_suite_pkcs7 -j1` if the
   binary is stale, compile `/app/repro.c` as above, run it, observe the
   abort.
2. **Localise**: study the PKCS#7 parse/cleanup lifecycle. Trace what the
   cleanup routine actually releases, which fields of the object it resets
   afterwards, and which fields a subsequent parse of a zero-signer message
   does and does not touch, and where the stale pointer comes from that the
   second cleanup hands to the allocator twice. Understand *why* the crash
   needs multiple signers in the first message before you patch.
3. **Fix** with the smallest possible change, rebuild
   (`cmake --build build --target test_suite_pkcs7 -j1`), rerun the repro
   until it prints `REUSE-OK` and exits 0, and try a couple of variants of
   your own (different signer counts, a rejected message followed by a valid
   one) before you commit to it.
4. **Prove nothing else broke**: run the project's own test binaries that
   were built at image time — `./build/tests/test_suite_pkcs7` and
   `./build/tests/test_suite_x509parse` — and confirm every case passes. On
   the pristine tree the pkcs7 suite prints `PASSED (813 / 813 tests
   (5 skipped))` and the x509parse suite `PASSED (888 / 888 tests
   (58 skipped))`; your fix must leave them green.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that every tracked
  file except the single source file implementing the buggy cleanup is
  byte-identical to that commit (any other modification, added file or
  stray untracked file fails), that the submodules are still at their pinned
  commits, and that `/app/summary.md` exists and is non-empty;
- rebuild the project's own machinery from your tree and run the **project's
  regression test for this bug** (upstream added it with the fix; it is
  baked into the image at `/opt/golden` and planted into the test suite at
  grading time — it does not exist in this tree), requiring the whole pkcs7
  suite to print `PASSED (815 / 815 tests (5 skipped))` including the reuse
  case, and the x509parse suite to stay green;
- compile and run **three authored hidden programs** that drive the same
  object-reuse code path from inputs the upstream regression test does not
  use: deeper parse/free cycles with different signer counts, a rejected
  message between two valid parses, and single-signer / zero-signer message
  shapes. Each checks the real parsed content after reuse — signer counts
  and that no stale signer state survives — so merely avoiding the abort is
  not enough.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.