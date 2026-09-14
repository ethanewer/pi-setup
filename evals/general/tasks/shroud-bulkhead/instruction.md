# pnpm 11 lockfiles: scanner reports the package manager's own components

## Environment

- `/app/src` is a git checkout of **Trivy** (`aquasecurity/trivy`), a
  production software-composition scanner, pinned to a specific upstream
  commit. It is the real upstream tree with the bug described below still in
  it, plus one extra regression test related to that bug that the upstream
  project later added. Do **not** re-clone, re-fetch, re-checkout, or commit
  in this repository: your changes to the tree must be working-tree edits.
- The Go 1.26.3 toolchain (`go`) is installed on PATH and the repository's
  `go.mod` requires exactly `go 1.26.3`. All Go dependencies are already
  downloaded and the module/build caches are warm, so `go test` recompiles
  only what you changed. There is no guarantee of network access: everything
  you need is already on disk.
- The machine is budgeted at **one CPU** (`GOMAXPROCS=1` is set). Keep your
  test runs single-threaded.
- The project's own test harness is `go test` (`go help test` has the full
  details). A directory's `*_test.go` files are compiled into and run with
  that directory's package, and `-run <regexp>` restricts execution to the
  matching tests. The scanner's pnpm-lockfile module is
  `pkg/dependency/parser/nodejs/pnpm`; its suite is run with

  ```
  cd /app/src && go test -v -short ./pkg/dependency/parser/nodejs/pnpm/...
  ```

## The bug (as users hit it)

Recent pnpm releases (pnpm 11 and newer) write the project's `pnpm-lock.yaml`
as **more than one YAML document inside a single file**: documents are
separated by a line containing `---`. The first document describes the
package manager's own environment (pnpm itself and its per-platform binary
packages), and a later document describes the scanned project's actual
dependencies.

The scanner ignores that structure. Scanning a Node.js project with such a
lockfile produces a dependency report that:

- lists the package manager's own components as if they were dependencies of
  the scanned project: `pnpm`, `@pnpm/exe`, `@pnpm/linux-x64`,
  `@pnpm/win-x64`, `@reflink/reflink`, `detect-libc` and friends, and
- omits the project's real declared dependencies, which are missing from the
  report entirely.

A correct scan of a project locked with such a `pnpm-lock.yaml` must report
the project's declared dependencies and must never report the package
manager's own machinery.

## Deliverables (create both, exactly at these paths)

1. **`/app/repro.sh`** — an executable, self-contained Bash script that
   reproduces the misbehaviour and proves it is gone. Contract:

   - Interface: `/app/repro.sh [REPO]`, where `REPO` is the root of a
     checkout of this tree and defaults to `/app/src`. The script must work
     when given a scratch copy of the tree, not just `/app/src`.
   - The script must **not modify `REPO`**: do all of its work in a fresh
     scratch copy under `/tmp`.
   - It must drive the scanner's own parsing code. Concretely: write a
     lockfile fixture and a small `*_test.go` file into the scratch copy's
     pnpm lockfile module (`pkg/dependency/parser/nodejs/pnpm`), then run the
     module's own test harness with `-run` selecting only your test, e.g.
     `go test -v -short -run <your-regexp> ./pkg/dependency/parser/nodejs/pnpm/...`.
     Follow the style of the existing `*_test.go` files in that directory.
   - Exit 0 **iff** the scanner parses your fixture correctly: the project's
     declared dependency is reported and no package-manager component is
     reported. Any other outcome must exit nonzero. Print the harness output
     to stdout.
   - Must not use the network.

2. **`/app/repro-fixture.yaml`** — the multi-document pnpm lockfile fixture
   that `/app/repro.sh` feeds to the scanner.

## How the deliverable is judged

The verifier runs your reproducer twice:

- **against the pre-fix tree**: a scratch copy of the tree with the two
  parser sources restored to their original state before your changes. Here
  `/app/repro.sh` must **fail** (exit nonzero), because the bug is real and
  your fixture exposes it;
- **against the repaired tree** (`/app/src` after your fix): it must pass
  (exit 0).

A reproducer that passes or fails either way measures nothing and scores 0.
So build the failing case first — make the fixture, watch the scanner
misbehave on the unmodified code, then make it behave.

## Acceptance criteria

- `/app/repro.sh` (executable) and `/app/repro-fixture.yaml` exist and obey
  the contract above, including failing on the pre-fix tree.
- The scanner is fixed so that the full pnpm lockfile module suite passes:

  ```
  cd /app/src && go test -v -short ./pkg/dependency/parser/nodejs/pnpm/...
  ```

- Do not weaken the tree to make tests pass: do not skip, delete or edit the
  regression test that the tree already ships (the verifier checks the golden
  test files byte-for-byte against the upstream originals), do not replace
  the `go` tool, and leave the repository at its pinned commit. Keep your
  changes to the tree confined to the pnpm lockfile module; unrelated
  modifications fail the check.