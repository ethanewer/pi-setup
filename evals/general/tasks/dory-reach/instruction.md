# PEP 621 pyproject.toml dependencies are reported under the wrong names

## Situation

`/app/src` is a shallow, pinned clone of the trivy repository
(`https://github.com/aquasecurity/trivy`) at upstream commit
`748a639b1d436a0566d325a4233ca13baf4cbd60`, checked out in detached HEAD.
There is **no network** at trial time: `git fetch`, `curl` and any other
network use will fail.

The Go toolchain (go 1.26.3) is installed at `/opt/go` and is on `PATH`, with
`CGO_ENABLED=0` and `GOEXPERIMENT=jsonv2` already exported. Those settings are
required by this toolchain and must be left untouched. Every project dependency
is hash-pinned by the committed `go.sum` and is already cached in the image, so
building and testing work fully offline. The repository's own unit tests for
the Python dependency parsers run with:

```
cd /app/src
go test -v -short ./pkg/dependency/parser/python/...
```

That is the harness that decides whether the bug is present. After the first
run everything is compiled, so further runs take a few seconds.

## The bug

Trivy reads Python dependencies from several manifest formats and matches them
against lockfiles so that a scan reports one canonical name per package. For a
`pyproject.toml` that declares its dependencies in the PEP 621 style — a
`[project]` table whose `dependencies` key is a list of strings such as
`"Flask(>=1.0,<2.0)"`, `"typing_extensions>=4"` or `"ruamel.yaml (>=0.18)"` —
the parser records each dependency name **exactly as typed**:

- `Flask` is reported as `Flask`,
- `typing_extensions` is reported as `typing_extensions`,
- `ruamel.yaml` is reported as `ruamel.yaml`.

Every other Python source of names in this codebase (the poetry lockfile
parser, the pylock parser, and the older pyproject mapping form) reports the
same packages under their **normalized** spelling: lowercase, with every run of
`.`, `_` or `-` characters collapsed to a single `-`. So `Flask` should come
out as `flask`, `typing_extensions` as `typing-extensions` and `ruamel.yaml` as
`ruamel-yaml`, always — regardless of how the author happened to type them in
the manifest.

The consequence is visible to users as inconsistent scans: a project that
mixes manifests shows the same package twice in one report, once under each
spelling, and the manifest dependencies never line up with the lockfile's
normalized names. Package-version alignment and vulnerability matching for
those entries silently miss.

## What you need to do

1. **Write your own failing reproduction.** Create a Go unit test at exactly
   `/app/src/pkg/dependency/parser/python/pyproject/repro_test.go` with its
   input fixture at exactly
   `/app/src/pkg/dependency/parser/python/pyproject/testdata/repro.toml`.
   Your test must feed the parser a `pyproject.toml` whose PEP 621
   `dependencies` list uses at least two distinct non-normalized spellings —
   a package name containing capitals, and a package name containing `.` or
   `_` separators (you may use constraint suffixes such as `>=4` or
   `(>=0.18)` on them; only the NAME is asserted) — and assert that the parsed
   dependency set contains the **normalized** spellings of those packages
   plus any fully-normalized ones you include. Model your test on the existing
   test file in that same package: parse with the parser's `Parse` entry point
   and compare against the `...Project.Dependencies.Set` field. With the code
   as shipped this test must FAIL: that failure, observed before you change
   any source, is your reproduction. Write it, run it, and confirm it fails
   first.
2. **Fix the parser in the checked-out tree** so that every PEP 621 dependency
   name from a `dependencies` list is reported in the normalized spelling
   (lowercase, runs of `.`/`_`/`-` collapsed to `-`), while everything that
   currently works keeps working. Drive your work with `go test`: your
   reproduction must pass and the whole Python dependency parser test scope
   must report success (exit status 0, no `FAIL`, no `panic:`). Under the
   fixed parser, a manifest listing `Flask`, `typing_extensions` and
   `ruamel.yaml` yields `flask`, `typing-extensions`, `ruamel-yaml`.

## Constraints

- Network is unavailable; everything needed (toolchain, pinned dependencies,
  repository) is already in the image.
- The clone at `/app/src` is the deliverable. Fix the bug in place only: do
  not rewrite history, do not fetch or add remotes, do not commit or stage,
  do not touch build or dependency files (`go.mod`, `go.sum`), and do not
  modify, delete or rename any file that already exists in the checkout —
  the project's own tests and fixtures included. The only files you may add
  are the reproduction test and its fixture named above; the only file you
  may modify is the parser source that needs the fix.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. Tree provenance: the tree is still the pinned parent commit (exactly one
   commit reachable, no fetched history), the upstream fix commit is not
   reachable, nothing was deleted or staged, no tracked file was touched
   except the one parser source file that needed the fix, and exactly your
   two reproduction files were added.
2. Your own reproduction, run against the parent's parser source (the
   original, buggy code, restored from a pristine copy): it must FAIL with a
   test-assertion mismatch, not with a build error.
3. The project's own pyproject parser suite, including the upstream
   regression test for this bug (restored from the fix commit at verify
   time): it must pass against your repaired tree — proving the fix is the
   real fix and broke nothing else in the module.
4. Your reproduction against your repaired tree, plus two authored hidden
   cases that exercise the same code path from spellings the upstream
   regression test does not use: all must pass.

Deliverables: the repaired `/app/src` tree, the reproduction test at
`/app/src/pkg/dependency/parser/python/pyproject/repro_test.go`, and its
fixture at `/app/src/pkg/dependency/parser/python/pyproject/testdata/repro.toml`.