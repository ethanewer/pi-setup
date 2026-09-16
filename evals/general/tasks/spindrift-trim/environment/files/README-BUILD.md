# Environment notes (spindrift-trim)

You are inside a container with a real upstream repository checked out. This
README is a cheat sheet for the preinstalled toolchain; it intentionally says
nothing about the bug. Read `instruction.md` for the task.

## Toolchain

- Go 1.26.8 is at `/usr/local/go/bin/go`, already on `PATH`.
- Go's module sources live in `/opt/gocache/pkg/mod`, its build cache in
  `/opt/gocache/build` — both pre-warmed and writable by you. Everything the
  `render` package needs to compile and run is already cached:
  **there is no network**, so never run anything that would fetch.
- `cpus = 1`: one vCPU. First compile of the `render` package takes a couple
  of minutes; incremental recompiles after a one-file edit are much faster.
  Prefer `-test.run` filtered runs while iterating.

## Running the project's tests

Run from the repository root (`/app/src`):

```sh
cd /app/src
go test -v github.com/gin-gonic/gin/render -test.run 'TestRenderString'
# or the whole render package suite:
go test github.com/gin-gonic/gin/render
```

- A passing run ends with `ok  	github.com/gin-gonic/gin/render`.
- A failing run ends with `FAIL` and per-test `--- FAIL:` blocks showing
  `expected: ...` / `actual: ...`.
- Tests live in `/app/src/render/*_test.go` — read them to learn how the
  project exercises its own renderers (in-process recorders via
  `httptest.NewRecorder` and real local servers via `httptest.NewServer`).

## Repository etiquette

- `/app/src` is a git worktree detached at a pinned upstream commit. Do not
  commit, fetch, pull, rebase or modify `.git` in any way; the verifier
  checks that the tree still sits at the pinned commit and that the file
  bytes match it.
- Do not add, remove, move or rename files inside `/app/src`; use `/tmp` for
  scratch work.
- `go test` never modifies the tree it runs from, so you can freely copy
  `/app/src` to `/tmp` (as your reproduction should) and test there.