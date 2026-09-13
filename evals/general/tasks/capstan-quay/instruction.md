# A front-matter-only page leaks its raw front matter into the rendered output

## Situation

`/app/src` is a shallow, pinned clone of the **Hugo** static site generator
repository from `https://github.com/gohugoio/hugo`, checked out at an
August-2023 development commit exactly as upstream had it at that point. Go
1.27.1 is installed (`/usr/local/go/bin` is on `PATH`), and the Go module and
build caches are already warm under `/opt/gopath` and `/opt/gocache` — the
full `hugolib` package and its test binary have been compiled once, so the
project's own test runner works incrementally and offline. There is **no
network** at trial time: everything you need is already in the image; `go`
cannot download anything and `git fetch` will not work.

## The bug

A Hugo content page is a Markdown file with an optional front-matter block
(YAML between `---` lines, or TOML between `+++` lines) followed by the page
body. When a layout prints the page's raw content — the `{{ .RawContent }}`
variable gives the un-rendered source text of the page body — a page whose
body is empty must contribute nothing.

That is not what happens for a page that consists of **only** front matter
and no body at all (the front matter block runs to the end of the file). The
rendered output for such a page contains the raw front-matter text itself:
the `---` (or `+++`) delimiters and the front-matter keys and values all leak
into the output. For example, given

```
---
title: "empty"
---
```

the page's `{{ .RawContent }}` renders as the full string
`---\ntitle: "empty"\n---` instead of the empty string. Pages that have any
body after the front matter are unaffected.

## Reproducing the failure

A ready-made probe, `/app/probe_test.go`, is a small test in the project's
own test framework (a textar fixture site with a front-matter-only page, a
page with a body, and a layout that prints `{{ .RawContent }}`). Copy it into
the tree and run it with the project's own test runner from the repo root:

```
cp /app/probe_test.go hugolib/probe_test.go
cd /app/src
go test -vet=off ./hugolib -run TestCapstanQuayRawContentLeakProbe -v
```

While the bug is present this prints a FAIL for the front-matter-only page
with a container roughly like `BEGIN---\ntitle: "weird-key"\n---END` (the
layout markers with the raw front matter between them). The flag `-vet=off`
is required: this 2023-era tree does not satisfy the current toolchain's
static checks, so without it the test build aborts before running anything.
The tree's own page tests live in `hugolib/page_test.go` and friends under
`hugolib/`; you are expected to work with those and the probe, not to run the
entire hugo test suite (it needs external tools that are not installed and is
far too slow without them).

## What you need to do

Fix the checked-out tree at `/app/src` so that a page that consists only of
front matter renders an **empty** raw content, in every place `{{ .RawContent }}`
is used:

- any front-matter format (YAML `---` or TOML `+++`), any keys, at any page
  path (root, section, dated folder) must yield the empty body — none of the
  front-matter text may leak into the output;
- a page that *does* have a body must keep rendering its raw source exactly
  as before, and other page behaviour (front matter parsing, dates, summaries,
  paths, output files) must not change.

Drive your work with the project's own test runner from `/app/src`, the same
way you reproduced it. When the bug is gone, the probe passes.

## Constraints

- Network is unavailable; everything you need is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier checks that the working tree is still at the pinned commit,
  that no history was fetched or added, that no tracked file was deleted,
  that the only modified tracked files are non-test source files under
  `hugolib/` (at least one such modification must be present — fixing this
  bug means changing page handling source, not test files or configuration),
  and that the test-harness helper `hugolib/integrationtest_builder.go` is
  untouched.

## What the verifier checks

1. The tree is still at the pinned commit, the working clone contains no
   other history (nothing was fetched or added), no tracked file was deleted,
   only non-test source files under `hugolib/` are modified (at least one),
   and the test-harness helper is untouched.
2. The project's own regression test for this behaviour passes. That test is
   the fix-era version of the raw-content page test, kept out of the tree at
   `/opt/golden/` and copied in by the verifier; it FAILS on the untouched
   tree and must PASS after your fix.
3. Two authored hidden cases with inputs the regression test does not use
   (TOML front matter in a section; a long YAML front-matter block in a
   dated path) pass, together with the probe.
4. A slice of the project's own existing page/front-matter tests, which
   passes on the pristine tree, still passes after your change.

Deliverable: the repaired `/app/src` tree.