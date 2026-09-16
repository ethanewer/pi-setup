# Building and testing Mbed TLS in this container

This tree is a plain-make Mbed TLS source checkout (3.6-era). This file is the
map you need to find your way around the build and its test machinery.

## Layout (what matters here)

- `library/` — the library sources (libmbedcrypto, libmbedtls, libmbedx509).
  `make -j1 lib` builds them in place; object files and static libraries land
  here and are git-ignored.
- `include/` — public headers. `include/mbedtls/mbedtls_config.h` is the build
  configuration (compile-time limits like `PSA_VENDOR_ECC_MAX_CURVE_BITS` live
  here as defaults; do not touch it).
- `tests/suites/` — the test suites. Each suite is a pair of files:
  `<suite>.function` (the C test functions) and `<suite>.data` (the test
  cases, in a compact text format described below).
- `tests/` — the built suite executables (`tests/test_suite_<name>`), plus
  the Makefile and scripts that generate them.
- `framework/` — a git submodule with shared test glue; it is checked out and
  needs no attention.

## How a test suite is built and run

The suite executable is **generated**: at build time the project's
generator (`tests/scripts/generate_test_code.py`) compiles
`<suite>.function` + `<suite>.data` down into a C file, and the **data file
is embedded into the resulting test binary**. Consequences:

- `make -C tests test_suite_psa_crypto_util` builds (or rebuilds) only that
  suite. It is the suite this task is about: its `.function` file wraps the
  PSA ECDSA signature format-conversion API surface, and its `.data` file
  holds the cases.
- If you edit the `.data` file, you MUST rebuild the suite before running it
  — otherwise you will run the old embedded cases.
- Run a suite with `./tests/test_suite_psa_crypto_util` (or pass a filter
  like `./tests/test_suite_psa_crypto_util "ECDSA"`). A passing run ends
  with `PASSED (N / N tests (0 skipped))`.

## Test data file format (the .data files)

Each case is a block of two lines plus a blank line:

```
<test name, free text>
depends_on:<config symbol list>            <- optional; omit to always run
<function name>:<arg1>:<arg2>:...:<expected return code>
```

Arguments are typed by the generator: integer arguments are bare numbers,
`data_t` arguments are double-quoted lowercase hex strings, and the expected
return code is either `0` for success or a `MBEDTLS_ERR_*` macro name. For
example:

```
ECDSA Raw -> DER, 256bit, Success
depends_on:PSA_VENDOR_ECC_MAX_CURVE_BITS >= 256
ecdsa_raw_to_der:256:"11111111111111111111111111111111111111111111111111111111111111112222222222222222222222222222222222222222222222222222222222222222":"30440220111111111111111111111111111111111111111111111111111111111111111102202222222222222222222222222222222222222222222222222222222222222222":0
```

Watch the argument units: hex strings are hex (2 chars per byte), `data_t`
lengths are bytes, and the first integer argument after the function name is
the `key_bits`/bit-size argument of the API under test.

## Environment notes

- `cpus = 1`: one vCPU. Use `make -j1`. Everything pre-built at image build
  time is incremental-friendly: touching one source file only recompiles that
  file, and regenerating one suite takes seconds.
- There is no network. Do not try to fetch anything.
- Do not commit, fetch, rebase, or otherwise modify `.git`; the tree is a
  single-commit shallow clone on purpose. Edit the working tree only.
- The verifier rebuilds the suite from scratch, so a reproduction that lives
  only in a hand-tweaked binary will not survive — the work is the `.data`
  and source changes.