# Task environment notes (shroud-bulkhead)

You are inside the task container for the Trivy pnpm-lockfile task. See
`/app/instruction.md` for the actual task.

## What is here

- `/app/src` — a shallow git checkout of `aquasecurity/trivy`, detached at the
  pinned parent commit (bug present). All your work on the scanner happens as
  working-tree edits here. Do not commit, re-clone, or re-checkout.
- `/app/.pristine/pnpm/` — the original (pre-bug-fix) parser sources as
  shipped. Used by the verifier to reconstruct the pre-fix tree; treat as
  read-only.
- `/opt/go/bin/go` — the Go 1.26.3 toolchain (the repo's `go.mod` requires
  exactly `go 1.26.3`). On PATH. All module builds are already cached under
  `/opt/builder` and are single-threaded (`GOMAXPROCS=1`).

## Useful facts

- Project test harness: `go test` (see `go help test`). A directory's
  `*_test.go` files are compiled as tests of that directory's package;
  `-run <regexp>` selects tests by name.
- The pnpm lockfile module: `pkg/dependency/parser/nodejs/pnpm` inside
  `/app/src`. Its suite:
  `cd /app/src && go test -v -short ./pkg/dependency/parser/nodejs/pnpm/...`
- Everything is offline; do not rely on network access.
- The image is one CPU. Do not start parallel test runs.
- Example fixtures and expected results live in that module's `testdata/`
  directory and `parse_testcase.go`.