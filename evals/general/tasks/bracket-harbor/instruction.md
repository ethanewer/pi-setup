# bracket-harbor: repair a broken query engine build

`/app/bh/` is a self-contained Go 1.22 module ("bh", stdlib only) for a small
query engine over flat event stores: a lexer, an ast package, a parser, a
canonicalization/evaluation package, an index/planner, a row store, a
schema registry, a report renderer, a config loader and a CLI (`cmd/bh`).
The tree has a committed git history (built incrementally) and, until
recently, a fully green `go build ./... && go vet ./... && go test ./...`.

**It is no longer green.** One package's test suite is failing. The failing
test output, taken from running `go test ./...` at the repository root, is:

```
--- FAIL: TestConditionGrouping (0.00s)
    query_test.go:33: case 0: "p = 1 OR q = 2 AND r = 3" groups as "and(or(eq(p, 1), eq(q, 2)), eq(r, 3))", want "or(eq(p, 1), and(eq(q, 2), eq(r, 3)))"
    query_test.go:33: case 1: "p = 1 OR q = 2 OR r = 3 AND s = 4" groups as "and(or(or(eq(p, 1), eq(q, 2)), eq(r, 3)), eq(s, 4))", want "or(or(eq(p, 1), eq(q, 2)), and(eq(r, 3), eq(s, 4)))"
FAIL
FAIL	bh/internal/query	0.002s
FAIL
```

The failing tests are the specification: they encode the language's
documented semantics, and they passed in the past. A regression in library
code changed the behavior — the failure surface is not where the cause
lives. Your job is to repair the source tree so that the whole suite is
green again, without touching the tests.

## Environment

- Go 1.22 is installed and configured; the module has no external
  dependencies, so everything runs offline (`go build ./...`,
  `go vet ./...`, `go test ./...` all work from `/app/bh/`).
- The repository at `/app/bh/` has real, intact git history. `git log`,
  `git diff` and `git show` are the intended debugging tools; the regression
  was introduced by a recent refactor commit, and the history will show you
  exactly how the tree evolved to its current state. Do **not** rewrite,
  squash or re-init that history.
- The repository is Go 1.22 (`go 1.22` pinned in `go.mod`); keep it that
  way.
- There is no network access. Everything you need is already on disk or in
  the Go standard library.
- A CLI is included: `bh canon "<condition>"` prints the canonical form of
  a condition and `bh select "<query>"` renders a small projection — handy
  for experimenting, not required.

## Deliverables

1. **The repaired tree at `/app/bh/`** such that, from the repository root:

   ```
   go build ./...
   ```
   exits 0, `go vet ./...` exits 0, and `go test ./...` exits 0 with no
   test failures anywhere.

   Constraints on the repair:
   - Do not modify, delete or rename any existing `*_test.go` file; the
     fix belongs in library code, and the verifier checks that the test
     seams are untouched.
   - Do not delete source files, shrink the repository below its current
     scale (5000+ lines of Go across 8-12 packages), or change
     `go.mod`.
2. **`/app/fix.md`** — a written report of the repair: what was failing,
   the root cause (which commit/introduced it, in which package, and why
   the symptom appeared in a different package), what you changed and how
   you verified the fix. A few hundred characters is the minimum bar; more
   detail is better.

## Grading

The verifier re-runs `go build ./...`, `go vet ./...` and `go test ./...`
on the delivered tree, confirms the grouping test that was failing now
passes, checks `/app/bh/` still has its history/intact scale/go 1.22 pin,
checks `/app/fix.md` exists with a real write-up, then mounts two
additional contract-test fixtures into the tree and re-runs the whole
suite. Everything must pass.