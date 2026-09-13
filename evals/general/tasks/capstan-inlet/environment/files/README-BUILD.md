# Build notes for the trivy tree at /app/src

This tree is `aquasecurity/trivy` (Go), checked out detached at a pinned
commit with a single-object shallow history. It is complete and editable.

## Toolchain

- Go 1.26.3 at `/opt/go/bin/go` (on `PATH`), matching `go.mod`'s `go 1.26.3`.
- All module dependencies are hash-pinned by the committed `go.sum` and have
  already been downloaded into the warm module cache
  (`GOMODCACHE=/opt/gomodcache`; the compile cache is `GOCACHE=/opt/gocache`).
  The trial has **no network**: `go` reads the caches only, which is fine.

## Running the .NET dependency parser's own test suite

```bash
cd /app/src
go test -v -short ./pkg/dependency/parser/dotnet/core_deps/
```

The run compiles only the parser package and what it imports (no separate
`go build` step; `go test` handles it). A cold recompile of this closure
takes roughly half a minute on one CPU; afterwards the build cache makes
reruns near-instant. The test binary runs with the package directory as its
working directory, so fixtures are referenced as `testdata/<file>`.

## Adding a scratch test

To try a hypothesis, drop an authored `zz_*_test.go` file and any fixtures
into the package directory (or its `testdata/`), run the command above, and
delete them again before finishing: the grader requires the final tree to
differ from the pinned commit in exactly one source file.

## Notes on the parser itself

The parser reads a `.deps.json` file (the .NET SDK's dependency-graph
artifact). `libraries` maps library IDs to records whose `type` is
`package`, `project` or `runtimepack`; `targets` holds per-target
dependency edges and runtime sections. The package list reported to the
scanner is built from `libraries`, and the dependency graph comes from
`targets`. What makes an application's packages "root"/"workspace"/"direct"/
"indirect" is decided entirely inside this package.