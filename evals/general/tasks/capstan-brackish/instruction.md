# An out-of-range `@` timestamp crashes `fd` instead of being rejected

## Situation

`/app/src` is a shallow, pinned clone of `fd` (`https://github.com/sharkdp/fd`),
a fast, user-friendly alternative to `find`, checked out at upstream commit
`fb0426fed164c5fa9cd04b5e4aa8d8c375efa1d0` (fd 10.4.2). The Rust toolchain
(1.98.1) and every dependency the project needs are already installed and
cached, and the project has been built once so your subsequent builds are
incremental. The trial has **no network**: `git fetch`, `rustup`, and `cargo`
downloads will not work; everything needed is baked into the image and the
environment variable `CARGO_NETWORK=off` is set to make that explicit.

## The bug

`fd` lets you filter files by their modification time. Timestamps given as a
Unix epoch value are written with a leading `@`, for example
`--changed-before @1707723412` (that value is 2024-02-12).

Supplying a **well-formed but too-large** Unix timestamp in an `@`-prefixed
argument to a file-age filter crashes the whole program instead of being
treated like any other unparseable date input. The search aborts immediately
with an unhandled panic about arithmetic overflow rather than reporting that
the timestamp cannot be parsed:

```
$ cd /tmp && fd --changed-before @18446744073709551615 .
thread 'main' panicked at src/filter/time.rs:45:18:
overflow when adding duration to `SystemTime`
```

The process exits with status 101 (Rust panic exit code). Any number that is
well formed — that is, a valid unsigned decimal integer — but simply too large
to fit the program's internal time representation triggers the crash. The
flag `--changed-within` is affected in exactly the same way. Scripts that pass
loosely validated timestamps die outright instead of receiving a parse error
they could recover from.

## Reproducing the failure

```
cd /app/src && cargo build
/app/probe_out_of_range_ts.sh
```

`/app/probe_out_of_range_ts.sh` runs the built `fd` binary with an
out-of-range `@` timestamp and reports whether the crash is present. While the
bug is present it prints the panic and exits with status 1.

The project's own test suite, which you can run with `cargo test` from
`/app/src`, contains a failing unit test that exercises exactly this
behaviour; it is the project's own regression test for the crash and it fails
on this checkout. You can run it on its own:

```
cd /app/src && cargo test out_of_range_unix_timestamp_is_rejected
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that an out-of-range
`@` timestamp given to `--changed-before` or `--changed-within` is rejected
gracefully — the same way any other string that is not a valid date or
duration is rejected — instead of panicking the process. The program should
report that the value is not a valid date or duration (its ordinary error
message) and exit with status 1 after printing it, like it does for
`--changed-before definitely-not-a-date`. Well-formed `@` timestamps that are
in range must keep working exactly as before, and the rest of the date/duration
parsing and filtering behaviour must be unchanged (durations like `2d3h`,
absolute dates like `2018-01-01 00:00:00`, and the `--change-older-than` /
`--change-newer-than` aliases are all handled by the same parser and must not
regress).

Drive your work with the project's own tooling from `/app/src`:

- `cargo build` builds the `fd` binary (`target/debug/fd`);
- `cargo test` runs the project's unit and integration test suites, both of
  which are self-contained and need no network.

The whole project test suite is green at the pinned commit except for the one
failing regression test that describes this bug; keep it green. One caveat:
the integration test `test_exec_nulls` (it exercises `--exec` output
interleaving, unrelated to time filters) is timing-sensitive and can fail
spuriously inside the trial container, which is capped at 1 CPU — it fails
there even on a pristine tree or on a fully correct fix, and it passes on a
multi-core machine. The verifier runs the suite with exactly that one test
skipped. If you see that test fail, ignore it; any other failure is a real
regression.

## Constraints

- Network is unavailable; everything needed is already installed.
- The clone at `/app/src` is the deliverable. Change only what the fix
  requires, in place. Do not rewrite history, add remotes, fetch, change build
  files, or modify the project's own tests. Do not touch the harness-owned
  directories `/opt/golden`, `/tests`, and `/solution`.
- The verifier checks that the working tree is still at the pinned commit
  `fb0426fed164c5fa9cd04b5e4aa8d8c375efa1d0`, that the clone still contains
  exactly that one commit (no history was fetched or added), that no tracked
  file was deleted, that the only modified tracked files are the project's own
  source files under `src/` (at least one such modification is present), that
  no new files were added under `src/`, and that the project's own regression
  test for this behaviour is still present and unchanged.

## What the verifier checks

1. Tree provenance: HEAD is still the pinned parent commit, the clone contains
   no other history, no tracked file was deleted, only source files under
   `src/` are modified (at least one), no new files under `src/`, and the
   project's own regression test for this crash is byte-identical to the
   upstream copy.
2. The project's own regression test for this behaviour passes (`cargo test
   out_of_range_unix_timestamp_is_rejected`).
3. The project's own full test suite still passes (unit + integration, with
the timing-sensitive `test_exec_nulls` skipped for the 1-CPU reason above).
4. Hidden cases exercising the same code path from inputs the regression test
   does not use: `--changed-before` with the out-of-range timestamp
   `@9223372036854775808`, `--changed-within` with `@18446744073709551614`,
   and a guard that a huge but in-range timestamp (`@9223372036854775807`)
   keeps working normally.

Deliverable: the repaired `/app/src` tree.