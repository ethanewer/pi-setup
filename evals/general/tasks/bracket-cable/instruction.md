# A copied request context must not lose what the framework recorded

## Situation

`/app/src` is a pinned, shallow clone of **gin** (`https://github.com/gin-gonic/gin`),
the web framework for the Go language, checked out in detached-HEAD state at
upstream commit `2e4d4f38962a6f15ae496d59b294f307eef95429`. That commit is a
real released upstream state; the tree there is exactly what the upstream
project shipped at that point.

The Go toolchain (go 1.26.8) and `make` are installed, and every
third-party dependency that the framework's own `go.mod` requires is already
downloaded, built and verified against the project's `go.sum` — the build
caches are warm. **There is no network at trial time**: `git fetch`, `curl`
and friends will fail. Everything you need is already in the image.

The project's test runner (run from `/app/src`):

```
cd /app/src && go test -v github.com/gin-gonic/gin -test.run '<name-prefix>'
```

`-test.run` accepts a regular expression over test names; the tests live in
`*_test.go` files at the repository root (for example `context_test.go`).

## The bug

gin's `Context.Copy()` promises — per its own documentation: *"Copy returns a
copy of the current context that can be safely used outside the request's
scope. This has to be used when the context has to be passed to a goroutine"*
— that code can snapshot a request context and keep using the snapshot
after the request is over. That promise is currently broken.

When a context is copied, everything the framework had recorded on the
original context is silently dropped:

- **Attached errors vanish.** Errors that were recorded on the context (by
  validation, by earlier middleware, or by the application itself, via
  `Context.Error(...)`) are completely absent from the copy.
- **Negotiated media types revert to empty.** The set of formats the request
  negotiated for the response (recorded via `Context.SetAccepted(...)`) is
  empty on the copy, even though the original had a populated list.

So a handler that hands the context to a background goroutine, or keeps a
snapshot for later error reporting, sees a context that looks like a fresh
request on which nothing ever happened: error responses are generated from no
errors, and content negotiation falls back to nothing. The copy must behave
like the original for everything that had already been recorded on it.

## Reproducing the failure

A scratch reproduction probe ships at `/app/probe_context_copy_test.go`. Copy
it into the repository root and run it:

```
cp /app/probe_context_copy_test.go /app/src/
cd /app/src && go test -v github.com/gin-gonic/gin -test.run 'TestProbeContextCopyRecoversAttachedErrors'
```

That test records one error on a context, copies the context with
`Context.Copy()`, and checks that the copy still carries the error. On this
checkout it FAILS. When you are done, remove the probe file from the tree
again:

```
rm /app/src/probe_context_copy_test.go
```

You may also write your own temporary tests with the same runner. Note that
the runner compiles every `*_test.go` file it finds at the repository root,
so leave no scratch files behind when you finish.

One tip so you do not chase a red herring: a few tests elsewhere in the
suite check that the sandbox's file permissions block writes, and those
fail merely because this container runs as root. They are unrelated to the
bug above; ignore them and scope your verification to the context behaviour.

## What you need to do

Fix the framework in the checked-out tree at `/app/src` so that
`Context.Copy()` produces a context that keeps everything recorded on the
original — errors already attached (their messages, types and metadata, in
order) and the negotiated media-type list — while later mutations on the
copy must not leak back into the original and later mutations on the
original must not leak into the copy. Contexts that had no errors and no
accepted formats must still copy cleanly.

Do **not** change the framework's public API, its build files, or the
`go.mod`/`go.sum`; change only what the fix requires, in place. Do not
commit anything, do not rewrite history, do not add remotes, do not fetch.
Make sure the reproduction `go test` commands pass on your repaired tree
before you finish.

## Deliverable and verdict

Deliverable: the repaired `/app/src` tree, still at the pinned commit, with
no scratch files left behind.

The verifier checks, in its own way:

1. **Provenance** — the tree is still exactly at commit
   `2e4d4f38962a6f15ae496d59b294f307eef95429`: no history rewrite, no new
   remotes, and the only modified file is the one the fix requires; no new
   files may be left in the tree.
2. **The project's own regression test** for this behaviour (extracted from
   the upstream fix and stored at `/opt/golden/`; harness-owned, do not
   touch) — it must pass against your repaired tree.
3. **The project's existing context test suite** — every `TestContext*`
   test in the checkout's own `context_test.go` must still pass.
4. **Hidden cases** — additional tests over the same code path with inputs
   the upstream tests do not use.