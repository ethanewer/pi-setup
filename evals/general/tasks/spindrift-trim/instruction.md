# spindrift-trim

You are working inside a real open-source codebase: **gin** (the Go web
framework, `gin-gonic/gin`), checked out at a pinned historical commit in
`/app/src` (the working tree starts clean). There is a bug in how one of this
framework's renderers frames HTTP responses. Your job is to find it, fix it in
the working tree, and prove the fix with the project's own test tooling. You
are deliberately **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- Go 1.26.8 is installed at `/usr/local/go/bin/go` and on your `PATH`.
  Go's caches are pre-warmed and shared at `/opt/gocache` (module sources under
  `/opt/gocache/pkg/mod`, build cache under `/opt/gocache/build`); the image
  was built with them already populated, so the render module compiles and
  runs **without network access**. Do not fetch or install anything.
- The tree lives at `/app/src` and is writable by you, but **do not commit,
  fetch, push, rebase, graft or otherwise modify `.git`** — the working tree is
  detached at the pinned commit and must stay there. Do not rename, move or
  delete files, and do not leave scratch files inside `/app/src` (use `/tmp`).
- `cpus = 1`: one vCPU. Compiling the render package from scratch takes a
  couple of minutes; after a small edit only the changed file is recompiled,
  which is fast. Prefer filtered test runs while iterating.
- The project is a Go+ module (see `go.mod` in the repo root, whose `module`
  line names `github.com/gin-gonic/gin`). The project's own test runner is the
  Go test command, run from the repo root:
  - one package's whole suite: `go test github.com/gin-gonic/gin/render`
  - a filtered subset: `go test -v github.com/gin-gonic/gin/render -test.run
    '<name>'`
  A passing run ends with a line like `ok  	github.com/gin-gonic/gin/render`;
  a failing run ends with `FAIL` and per-test `--- FAIL:` blocks showing
  `expected: ...` / `actual: ...`. The render package's tests live in
  `/app/src/render/*_test.go` and are your reference for how the project
  exercises its own renderers. They use only in-process tools (`httptest`
  recorders and `httptest.NewServer` local servers) and never need the
  network.

## The bug (user-visible symptom)

The framework lets applications serve **raw byte payloads with a
caller-chosen content type** — for example generated images, exported
documents or binary downloads. Applications build such a response through the
framework's raw-data renderer, passing the bytes and the content type; the
renderer is supposed to write the response including everything a client needs
to consume it.

On this tree, responses produced through that renderer are broken in a way
that strict HTTP clients, HTTP caches, and middleware notice immediately:
**even though the exact size of the payload is known before the first body
byte is written, the response carries no declared length**. Clients that rely
on the declared length see the header missing or empty. Depending on the
client, that means the response is refused outright, or falls back to chunked
framing, or cannot size buffers and progress indicators. Small payloads can
mask the symptom because other layers happen to leave framing hints; the
renderer itself is what must declare the length.

The affected behaviour is: **a response rendered as raw data with a known,
non-empty byte payload must declare an exact Content-Length header equal to
the payload's byte length, alongside its content type, before the body goes
out** — deterministically, for any payload size. (For an empty payload the
renderer does not need to set the header at all.)

## Your job

1. **Write a failing reproduction first.** Before you change any source code,
   write `/app/repro.sh` — your own minimal reproduction of the symptom
   described above. Its contract:

   - It must honour an environment variable `GIN_SRC` naming the gin source
     tree root to test, defaulting to `/app/src` when unset.
   - It must work with an **unmodified** copy of that tree: it must copy the
     tree named by `GIN_SRC` into a fresh scratch directory under `/tmp`, and
     never modify the tree named by `GIN_SRC` itself.
   - It must add its own tiny test file to the copy's `render/` directory (a
     Go+ test, in the style of the existing `render/render_test.go`), run it
     through the project's own test runner (e.g. `cd <copy> && go test -v
     github.com/gin-gonic/gin/render -test.run '<your-test-name>'`), and print
     everything the runner prints, plus nothing else.
   - Its test must render a **non-empty** raw byte payload (a few hundred
     thousand bytes) through the framework's raw-data renderer with a
     caller-chosen content type, served over a **real HTTP connection**
     (`httptest.NewServer`), and assert that the response carries the exact
     `Content-Length` the payload requires, along with the content type and
     the expected body size. Use a payload size large enough that the
     renderer — not the server's incidental framing — is what supplies the
     length.
   - It must also exercise the renderer through the framework's in-process
     response recorder (`httptest.NewRecorder`, same style as the existing
     tests) with a binary payload, asserting the recorded response's
     `Content-Length` equals the payload byte length.
   - It exits 0 **if and only if** the test run passed in full (`ok` for the
     package, no `FAIL`). Against the broken renderer the run must fail with
     the header assertion mismatching (`expected: ...` vs `actual: ""`).
   - It must work no matter what the current working directory is when it is
     invoked, and must not touch anything outside its scratch directory.

   On the **unfixed** tree this script must fail: the length is never
   declared, so the assertions mismatch. Confirm that now, before fixing
   anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes, and so that the project's own render test suite
   passes. Fix the renderer itself, not the symptom in a wrapper: the graded
   checks exercise the renderer directly, through the project's own test
   machinery, from inputs your reproduction does not use (see Grading). Do
   not merely special-case your reproduction — a correct response framing for
   payloads of any size is what is graded.

3. **Break nothing else.** Every other renderer and every existing test in
   the `render` package must keep working exactly as before, and the whole
   package suite must be green.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; make no commits; do not modify the test files
   or any other file. The grader compares every file's bytes against the
   pinned commit's own blobs, so cosmetic side-changes also fail. Your two
   authored files `/app/repro.sh` and `/app/summary.md` live **outside**
   `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. Browse `/app/src/render/` and the existing `render_test.go` to learn which
   renderer serves raw bytes with a custom content type and how the project
   tests it.
2. **Reproduce first**: author `/app/repro.sh` per the contract, run it
   against the current tree, and watch it fail with the missing-length
   assertion. Try small payloads to see why incidental framing can mask the
   symptom, then size up.
3. **Localise** the bug by reading the renderer's source: where the response
   is assembled, what is written, and what a response should carry when the
   body length is known in advance. Understand *why* the length never gets
   declared before you patch.
4. **Fix** with the smallest possible change in that one source file, run
   `/app/repro.sh` again (it must now pass), then run the whole render
   package suite (must stay green).
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`, run after you finish) will, on
your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream fix
  commit is **not** reachable from this clone, and that every tracked file
  except the single source file the bug lives in is byte-identical to that
  commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty,
  executable and behave per their contracts;
- force a recompile of the whole module from your delivered sources (the
  shared build cache is cleared once) and run your `/app/repro.sh` against
  that repaired tree (it must pass) **and** against a pristine pre-fix copy of
  the tree baked into the image at `/opt/prefix-src` via `GIN_SRC=...` (it
  must fail — proving the symptom is real and your reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) and require it to pass, along with the whole
  pre-existing `render` package test suite;
- run authored hidden cases that exercise the same renderer from inputs the
  upstream regression test does not use.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.