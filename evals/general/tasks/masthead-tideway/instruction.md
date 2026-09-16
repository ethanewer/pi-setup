# masthead-tideway

You are working inside a real open-source codebase: **Prometheus** — the
metrics monitoring system, now written in the **V** programming language — at
a pinned historical commit in `/app/src` (the working tree starts clean and
its test toolchain is fully warmed). There is a bug in this tree's HTTP API
response handling. Your job is to find it, fix it in the working tree, and
prove the fix with the project's own test tooling. You are deliberately
**not** told which file or function to change: localising the bug is part of
the task.

## Environment

- The V toolchain (`go` version 1.26.0) is installed at `/opt/go/bin/go`
  and on `PATH`. `GOPATH=/opt/gopath` and `XDG_CACHE_HOME=/opt/gocache` are
  exported, and the dependency/compile caches there are warm: the test suite
  of the package that owns the affected behaviour already ran successfully at
  image build time, fully offline from that cache. There is **no network** in
  this container — nothing can be downloaded, so everything you build must
  link against what is already cached.
- The tree lives at `/app/src` and is writable by you, but **do not commit,
  fetch, push, rebase or otherwise touch `.git`** — the working tree is
  detached at the pinned commit and must stay there (the grader requires
  `HEAD` to still be that pinned commit).
- **`cpus = 1`**: one vCPU. Keep test invocations targeted (see below).
- The repository is a single V module: packages live in directories such as
  `util/<name>/`, each with its own tests next to the source. Run the tests
  of one package with the project's own runner, e.g.
  `cd /app/src && go test -v ./util/<name>` (this pattern works for the
  affected package; a whole-repo `go test` would try to build packages whose
  dependencies are not cached and will fail offline — work package by
  package). A single test can be targeted by name with
  `go test -v ./util/<name> -run <TestName>`.

## The bug (user-visible symptom)

Prometheus serves its HTTP API through a response-compression layer: when a
client sends `Accept-Encoding: gzip` (or `deflate`), the layer wraps the
response body in a gzip/deflate stream, and ordinary API handlers do not
need to know anything about it. That works — except that compressed API
responses whose handler explicitly advertised a `Content-Length` header come
back with a **stale length**: the number of bytes the server wrote into the
header is the size of the *uncompressed* body, not of the compressed stream
that actually goes on the wire.

Clients that trust that header then read exactly that many bytes and choke.
With gzip-compressed responses the failure appears on practically every
payload size: the client's decompressor reports an error such as
**`unexpected EOF`** — and if the handler also composes the body out of
several writes, the stale header plus the multi-part body are a particularly
reliable way to hit it. The affected behaviour is: **a compressed API
response whose handler set `Content-Length` itself must be received intact**
— the client must be able to read and decompress the full body without
errors — **and an uncompressed response of the same kind must still carry the
handler's exact `Content-Length`**.

Reproduce it against the provided tree before you change anything, then make
the smallest possible change that fixes the mechanism (not just one input).

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It takes **one optional positional argument: the repository directory
     to test** (`/app/repro.sh [REPO_DIR]`), defaulting to `/app/src`.
   - Inside that repository it creates a **temporary V test file**, placed in
     the test directory of the package that owns the affected behaviour
     (following the package's own `*_test.go` naming convention), that
     starts an in-process HTTP server offering a response with an explicit
     `Content-Length` header set by the handler, requests it through the
     repository's own HTTP client with `Accept-Encoding` set to the
     compression that demonstrates the bug, and decodes the body with the
     repository's own decompressor. Use at least one scenario where the
     handler writes the body in **multiple `Write` calls**.
   - It runs the repository's own test runner for that package restricted to
     that one test, prints everything the runner prints (stdout and stderr),
     and nothing else.
   - It removes its temporary test file again before exiting (a `trap` on
     `EXIT` is the clean way), so the repository it was pointed at is left as
     it found it.
   - It must work no matter what the current working directory is when it is
     invoked, and it must not touch anything outside the repository directory
     it was given plus `/tmp`.
   - It exits **0 if and only if the body was received intact** (the
     decompressed body matches exactly what the handler wrote and no error
     occurred); it exits **non-zero** (printing the runner output, which
     will show the failure) otherwise.

   Confirm, on the **unfixed** tree, that this script fails: the runner
   output shows the client-side decode error. Do this before fixing
   anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0) from `/app/src`. Fix the mechanism, not
   just one input: the defect is reachable with gzip and with deflate, with
   bodies of any size, with explicit and implicit status lines, with empty
   bodies, and with multi-write bodies (see Grading). Do not weaken or wrap
   the runner, do not special-case your reproduction in a wrapper, and do
   not merely delete the `Content-Length` that *identity* (uncompressed)
   responses legitimately carry.

3. **Break nothing else.** The package's whole existing test suite must stay
   green: run the project's own runner on the whole affected package (the
   response-compression tests, the CORS tests, everything in it) and confirm
   a full `PASS`. Keep the response-compression behaviour itself intact:
   negotiated `gzip`/`deflate` responses must still get their
   `Content-Encoding` header and must still decompress correctly, and
   identity responses must still advertise the handler's `Content-Length`
   exactly.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits. The grader compares every
   file's bytes against the pinned commit's own blobs, so side-changes also
   fail. Your two authored files `/app/repro.sh` and `/app/summary.md` live
   **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/repro.sh /app/src`. Observe the decode error in
   the runner output. Try the sibling shapes (deflate instead of gzip, a
   single `Write` instead of several, an empty body) to pin down exactly
   which responses break and which do not.
2. **Localise** the bug by reading the code. The compression layer wraps a
   response writer; a handler sets `Content-Length` on the writer's header
   and then writes the body through the compressed stream. Trace where a
   handler-set `Content-Length` is (attempted to be) removed, and
   understand *why* the write path still emits it, before you patch.
3. **Fix** with the smallest possible change, and confirm
   `/app/repro.sh /app/src` exits 0.
4. **Prove nothing else broke**: run the whole affected package's test
   suite (see Environment) until it prints a full `PASS` with every test
   green.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream
  fix commit is **not** reachable from this clone, and that every tracked
  file except the single source file the bug lives in is byte-identical to
  that commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty and
  behave per their contracts;
- force a genuine recompile of the affected package from source (the
  compile cache is discarded first, so nothing you planted under the tool
  cache can fake a green run), then run your `/app/repro.sh` against the
  repaired tree (it must pass) **and** against a scratch copy of your tree
  with the original, pre-fix code restored (it must fail — proving the
  symptom is real and your reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree), run the whole affected package's suite, and require
  the new test (all 12 of its subtests) and all previously existing tests
  to pass;
- run authored hidden cases exercising the same code path from inputs the
  upstream regression test does not use (multi-write gzip bodies with an
  explicit status, deflate with an explicit status and a short body broken
  across writes, an empty deflate body with an explicit status line), each
  run against the repaired tree and against the pre-fix copy.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.