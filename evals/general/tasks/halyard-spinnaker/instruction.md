# halyard-spinnaker

You are working inside a real open-source codebase: **Hugo**
(`gohugoio/hugo`), the static site generator, checked out at a pinned commit
in `/app/src` (working tree starts clean). There is a bug in this tree's
template engine. Your job is to find it, fix it in the working tree, and
prove the fix with the project's own test tooling. You are deliberately
**not** told which file or function to change: localising the bug is part of
the task.

## Environment

- Go toolchain 1.27.1 is installed at `/usr/local/go/bin` and on `PATH`
  (`go`, `git`). The repository pins every dependency itself (its own
  `go.mod` / `go.sum`); do **not** change those files.
- **There is no network** in this container. Everything needed is baked in:
  the Go module cache (`/opt/gomodcache`) and a warm Go build cache
  (`/opt/gocache`) were populated at image build time at this same commit.
  Any `go` command you run completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not
  commit, fetch, or otherwise modify `.git`.
- The Go caches and the working tree are writable by the container user.

## The bug (user-visible symptom)

Hugo lets a template *partial* pass data back to its caller: a partial can
contain a `return` statement, and when a page calls that partial the
returned value is inserted into the page at the call site.

There is a class of partial calls that silently (well, not silently) breaks
the whole site build. When such a returning partial is called with a
**falsy** argument — an empty dictionary (`dict`), an empty slice (`slice`),
an empty string (`""`), the number `0`, or `false` — Hugo aborts the entire
build instead of rendering the page. The build error looks like:

```
error calling partial: partial that returns a value needs a non-zero argument.
```

Nothing else is wrong: the same partial called with a truthy argument (a
non-empty dictionary, a non-empty list, any non-empty string, a non-zero
number, `true`) renders exactly as it should, and a partial that does not
use `return` accepts falsy arguments without complaint. Only the
"returns a value" partials are affected, and only when the argument they are
called with is falsy. The partial's body is never evaluated, so the value it
would have returned is lost and the page is missing its content.

Users of the affected Hugo version see this as: a site that built fine
yesterday stops building today because some call passes an empty value into
such a partial (for example a page variable that ended up empty, an empty
list from a data file, or a `0` value in front matter).

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It must honour an environment variable `HUGO_BIN` naming the Hugo
     binary to execute, defaulting to `/app/hugo` when unset.
   - It must create a tiny Hugo site in a fresh scratch directory under
     `/tmp`: a layout that calls a returning partial with a **falsy**
     argument, plus the partial itself (which uses `return` and returns a
     distinctive marker string), plus one content page.
   - It runs the Hugo build with `--quiet` and prints the rendered page.
   - It exits 0 if and only if the build **succeeds** and the rendered page
     actually contains the marker string that the partial returned;
     otherwise it exits nonzero (printing Hugo's output).
   - It must work no matter what the current working directory is when it
     is invoked.

   On the **unfixed** tree this script must fail: the build aborts with the
   error above. Confirm that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0, rendered page contains the returned
   marker). The same defect is reachable with *any* falsy argument and from
   any of the ways a falsy value can reach the call — an empty string coming
   from a page's front matter, an empty list coming from a data file, `0`
   or `false` computed by an expression, or a falsy value returned by yet
   another partial. Do not merely special-case one input in a wrapper
   script or in your repro: the regression test the grader runs and the
   hidden cases all drive the code path directly through the project's own
   template machinery.

3. **Break nothing else.** Everything else must keep working exactly as
   before: partials called with truthy arguments (including partials that
   return values), non-returning partials, `block`/`define` composition,
   templating in general. The project's own test suite must stay green.

4. **The graded tree must be byte-identical to the pinned commit except for
   the source files where the bug's fix genuinely lives.** Do not add,
   move, delete, rename or reformat any file; if you create scratch files to
   investigate, delete them before you finish; make no commits; do not
   modify `tests/`, `go.mod`, `go.sum` or any metadata file. The grader
   compares every file's bytes against the pinned commit's own blobs, so
   cosmetic side-changes also fail. Your two authored files `/app/repro.sh`
   and `/app/summary.md` live **outside** `/app/src` and are fine.

5. **Build the Hugo CLI from your fixed tree to `/app/hugo`** (this is what
   `/app/repro.sh` defaults to):
   `cd /app/src && go build -o /app/hugo` — then re-run `/app/repro.sh`.

6. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** first with the prebuilt binary the image ships for you at
   `/opt/prefix/hugo` (a pristine build of this exact tree — it has the
   bug). Scratch files go in `/tmp`, never inside `/app/src`; you may use
   `/opt/prefix/hugo` to drive the scenario while your tree is untouched.
2. **Localise** the bug by reading the code: trace what happens when a
   partial that contains `return` is called — where the decision is made
   that rejects the call, and how the call is wrapped so the return value
   can be captured. Understand *why* the rejection only fires for falsy
   contexts and why the value is lost, before you patch.
3. **Fix** with the smallest possible change, rebuild
   (`go build -o /app/hugo`), and confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: run a targeted slice of the project's own
   test harness with the project's test runner:
   `cd /app/src && go test -vet=off ./hugolib -run "TestPartialWithReturn|TestPartialCached|TestPartialInline|TestPartialInlineBase|TestTemplateTruth|TestTemplateFuncs|TestTemplateLookupOrder|TestTemplateManyBaseTemplates|TestTemplateNoBasePlease" -v`
   — every one of these passes on the pristine tree and must still pass
   after your fix.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the fix commit
  is not reachable in the clone, and that every tracked file except the
  source file(s) the bug's fix genuinely lives in is byte-identical to that
  commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/repro.sh` and `/app/summary.md` to exist and be non-empty;
- rebuild the Hugo CLI from your tree (your `/app/hugo` is discarded and
  rebuilt from the tree), then run your `/app/repro.sh` against that
  repaired binary (it must pass **and** print the rendered page) **and**
  against the pristine pre-fix binary at `/opt/prefix/hugo` (it must fail —
  proving the symptom is real and your reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree; it is the `TestPartialWithZeroedArgs` function in
  `hugolib/template_test.go`) into the tree, rebuild the test harness
  offline, and run it: the planted regression test must pass, and the
  project's existing partial/template tests listed in your working loop
  must still pass;
- run the rebuilt Hugo binary on **hidden cases** — sites that reach the
  same broken code path with falsy arguments the upstream test does not use
  (an empty string coming from front matter, an empty list coming from a
  data file, `false` computed by an expression, and a falsy value returned
  by another partial) — each must build with exit 0 and produce the
  byte-exact expected rendered page.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.