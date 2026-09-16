# flume: upgrade the CLI framework dependency

You are handed a working Go repository at **`/app/flume`**: a command-line tool
called `flume` that manages data pipeline runs. It has a real git history, a
green test suite, and a dependency on the `urfave/cli` command-line framework
that is pinned to an **obsolete major release** of that framework.

Your job: **upgrade the framework dependency to its current major series and
migrate every call site**, so that the repository builds and its tests pass
against the new API. The repository's own `docs/UPGRADE.md` documents the
framework's current major, the exact target version, and the breaking changes
that matter for this codebase — read it before you start.

## Environment

- Go 1.22 is installed. `git` is available.
- The container has **no network access**. The Go module cache
  (`/go/pkg/mod`) is pre-populated with everything the upgrade needs,
  including the target version's full dependency graph, so `go get`, `go mod
  tidy`, `go build` and `go test` all work offline. `GOPROXY=off` is set; an
  uncached lookup fails fast.
- Do not modify anything outside `/app/flume`.

## What must be true when you are done

1. `/app/flume/go.mod` requires the **current major series** of the framework
   (module path `github.com/urfave/cli/v3`, any v3.x release). The obsolete
   v1/v2 module must no longer be required.
2. `cd /app/flume && go build ./...` succeeds.
3. `cd /app/flume && go test ./...` succeeds — the repository's own tests must
   be migrated to the new API and stay green.
4. The repository's public surface is preserved:
   - `internal/app` still exports `Build()` (the framework's top-level command
     object) and `Execute(args []string) error`.
   - The CLI still exposes the subcommands `start`, `stop`, `status`, `list`
     and `inspect`, the global `--state-dir` flag, and the same output formats
     (see below).
   - The module path stays `flume.dev/tool`. Do not rename packages, delete
     tests, or change the behavior of `internal/engine` or `internal/state`.

## Output contract

Run records are JSON files in the state directory, one per run, named
`<run-id>.json`, with this schema:

```json
{
  "id": "run-...",
  "pipeline": "demo",
  "status": "running",
  "input": "in.csv",
  "output": "out.json",
  "workers": 3,
  "started_at": "2026-08-01T02:00:00Z",
  "finished_at": "2026-08-01T02:30:00Z",
  "error": ""
}
```

`status` is one of `pending`, `running`, `done`, `failed`, `stopped`.
`finished_at` and `error` are omitted when unset. The CLI output formats:

- `start <pipeline>` prints `started run <id> (pipeline <name>)`
- `stop <run-id>` prints `stopped run <id>`
- `status <run-id>` prints `run <id> status=<status>`
- `list` prints one `run <id> <pipeline> <status>` line per run; `list --json`
  prints a JSON array of run records
- `inspect <run-id>` prints a text block; `inspect <run-id> --format json`
  prints the full run record as JSON

Starting a pipeline that already has a running run fails unless `--force` is
given, in which case the previous run is marked `stopped` first. A missing
pipeline name or run id is a usage error.

## Notes

- The interesting part is the migration itself: the new major's API is a
  breaking rewrite, and every call site in the repository (including the
  tests) must move to it. The verifier will additionally run hidden tests that
  exercise the new API shape, so a superficial change to `go.mod` alone is not
  enough.
- `go get <module>@latest` will not resolve offline; use the exact target
  version named in `docs/UPGRADE.md`.
