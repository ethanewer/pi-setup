# Debug a real upstream bug in Syncthing

You are working inside a checkout of the real **Syncthing** file-sync program
at `/app/src`, pinned to a specific historical commit that still contains the
bug. This is an unfamiliar, real, moderately large codebase (a few hundred
Go source files under `lib/`). Localising the bug is part of the task — you
are deliberately not told which file or function to change.

## Environment

- Go 1.26.8 is installed at `/usr/local/go/bin/go` and on `PATH`. The project
  uses Go's module system: `go.mod` at the repository root declares the module
  and its dependencies. Third-party modules are already cached under
  `/opt/go-cache` (`GOMODCACHE`/`GOCACHE` both point there), and the build
  caches are warm, so `go build` / `go test` work fully OFFLINE.
  - The project's own test runner for a single package directory is
    `go test <package-dir> -run <pattern> -v` (see `go help test`); a test
    function in a `*_test.go` file looks like `func TestXxx(t *testing.T)`.
    The full-suite entry point (`go run build.go test`) is much slower —
    avoid it and work per-package.
  - After you edit a package's sources, the next `go test` on it recompiles
    that package; this sandbox has **one CPU**, so those compiles take
    minutes — plan edits carefully and reuse a single scratch test file.
- `git` is available; the tree is a detached single-commit worktree (its
  object store holds only this commit — nothing else can be referenced or
  fetched). **There is no network**: do not try to download anything, add
  remotes, or fetch.
- Do not modify, delete, or write into anything under `/opt` (the Go caches
  and any other pre-baked trees), `/usr`, or `/etc`. All of your work happens
  under `/app`. Do not `git commit`, create branches or tags, or modify the
  `.git` config. Scratch material goes under `/tmp`.

## The bug, as a user reported it

> “After the latest update, my shared folders suddenly start syncing
> everything: files that I had configured to ignore are being scanned and
> transferred. The log for the folder shows this error over and over:
> `open /home/alice/sync-folder/.stignore: too many levels of symbolic links`
>
> I keep my ignore rules in a separate file and `.stignore` is a symbolic
> link pointing at that rules file. That setup has worked for years and it
> is the recommended way to keep your ignore rules in a dotfiles
> repository.”

The affected behaviour: when the folder's `.stignore` is a symbolic link to
the real rules file, the folder's ignore patterns are **silently not
applied** — the scanner logs the `too many levels of symbolic links` failure
and continues anyway, so files that should be excluded are scanned and
synced. When `.stignore` is a regular file (the rules file is whatever it is
pointed at), the same patterns load and apply correctly.

## Your job

1. **Write your failing reproduction first.** Before changing any source
   code, create `/app/repro.sh` — executable, self-contained, reproducing
   the symptom described above through the project's own machinery. Its
   contract:

   - Takes **one optional positional argument**: the path to a Syncthing
     checkout to run against; default `/app/src`. Must work from any
     current working directory.
   - Self-contained: it may create temporary files inside the checkout it
     is given (for example a small `*_test.go` under `lib/`), and must not
     depend on files that exist only in `/app/src`.
   - Against a **buggy** checkout: exits non-zero and prints the observed
     diagnostic text (the line containing
     `too many levels of symbolic links`) to stdout.
   - Against a **fixed** checkout: exits 0 and prints evidence that the
     rules file was loaded through the symlink (e.g. a passing test line
     from the project's runner).

   Confirm **now**, before fixing anything, that on this tree
   `bash /app/repro.sh /app/src` fails exactly as above. After your fix the
   same command must pass.

2. **Fix the tree.** Make the change so the scenario genuinely works: ignore
   rules reached through a symlinked `.stignore` must load and apply, and
   the error must be gone. Fix the mechanism, not just one input — the same
   defect is reachable with the rules file stored in a subdirectory or
   outside the folder, and with the symlink spelled differently (the grader
   exercises those). Do not merely hide the error or special-case a test:
   the grader runs the project's own regression tests and existing suites
   against your tree.

3. **Break nothing else.** The project's existing ignore and filesystem test
   suites must stay green on your tree.

4. **Write `/app/summary.md`** — non-empty: the root cause (which mechanism
   refused to open the symlink and why), and what you changed.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree
   (uncommitted changes are expected and sufficient).
2. `/app/repro.sh` — your reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier runs after you finish, against your final tree, and asserts:

- provenance: the tree is still at the pinned commit (no commits/fetches);
- your `/app/repro.sh` passes against `/app/src` (exit 0, evidence) and
  fails with the `too many levels of symbolic links` diagnostic against a
  pristine unmodified pre-fix checkout the verifier keeps;
- the project's own regression test for this bug (added upstream in the
  commit that fixed it, so it is not present in this tree) passes when the
  verifier plants it into your tree;
- the project's existing `lib/ignore` and `lib/fs` test suites pass on your
  tree, and additional hidden cases exercising the same code path from
  different inputs pass as well.

Reward is binary: 1 if and only if every check above passes on your tree,
otherwise 0.