# capstan-roadstead

You are working inside a real open-source codebase: **jest**
(`https://github.com/jestjs/jest`), the JavaScript test framework, checked
out at a pinned commit in `/app/src` (detached HEAD, working tree clean,
exactly one commit in the clone). There is a bug in how jest's
glob-based file selection treats matcher options. Your job is to find it,
fix it in the working tree, and prove the fix with the project's own test
tooling. You are deliberately **not** told which file to change:
reproducing and localising the bug are part of the task.

## Environment

- Node.js 22 with npm. A standalone compile/test toolchain is installed
  at `/opt/tsapp`: TypeScript 5.9.3, the published `jest` 30.4.1 test
  runner, and the matcher libraries jest pins (`picomatch` 4.0.7 and
  `micromatch` 4.0.8) — the same versions the repository requires.
- **Do not rely on the network.** The trial has no network access:
  `git fetch`, `curl`, `npm install` and downloads will not work. The
  clone's origin remote has been removed; do not modify `node_modules`;
  do not run `npm install` inside `/app/src` (the monorepo is not set up
  for it).
- `cpus = 1`: one vCPU. Do not launch parallel builds or test runs.
- The tree at `/app/src` is shallow (a single commit) and detached at a
  pinned commit. Do not commit, fetch, or otherwise modify `.git`.
- Read `/app/README-BUILD.md`. Two helpers are provided:
  - `bash /app/repro.sh` — compiles the glob-matcher implementation
    straight out of `/app/src` and runs the reproduction (see below);
  - `bash /app/run-test.sh <file.test.ts>` — compiles any test file
    against the tree sources and runs it with jest.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  modify anything there.

## The bug (user-visible symptom)

jest resolves which files belong to a request — which test files match a
`--testPathPattern`-style glob list, which paths pass an include/exclude
filter, and which files should be transformed or covered — by converting a
list of glob patterns into a matcher function once per request. That
conversion can be given matcher options that change what matches, for
example `dot: false` to stop dotfiles (files starting with `.`) from
matching, or `nocase: true` to match case-insensitively.

In this tree, those options are silently ignored after the *first* time a
pattern is seen: matchers are cached per pattern, so a glob that was first
compiled with one set of options keeps behaving that way for every later
request, even when different options are passed. The stale behavior
depends on call order within a run:

- a glob first used with default options (dotfile matching **on**) keeps
  matching dotfiles for every later call, even one made with `{dot: false}`
  — so a file you tried to exclude by turning dotfile matching off is
  still matched, and files are silently selected with the wrong options;
- a glob first used with `{dot: false}` keeps *not* matching dotfiles even
  when a later call asks for the default behavior.

Reproduce it:

```bash
bash /app/repro.sh
```

On this tree the script prints `true true` and exits 1: the first call,
with default options, matches the dotfile `'.hidden.dotoption.js'`
(correct — dot matching defaults to on), and the **second** call, made
with `{dot: false}`, still returns `true` (wrong — with `dot: false` the
dotfile must not match). The two calls use the same glob and happen in the
same process, which is exactly when the stale cache bites.

## Requirements

1. Fix the tree so that `bash /app/repro.sh` prints `true false` and
   exits 0.
2. Every individual call must behave exactly like the `micromatch` package
   with the same globs and the same options: options given on a call are
   honored for that call and must not leak into later calls on the same
   glob; a call without options keeps the default behavior (dotfile
   matching on), no matter what earlier calls on the same glob received.
3. Fix the *cause*, not the symptom: make the caching of compiled
   matchers safe with respect to the per-call options. Do not hardcode the
   specific repro inputs, and do not switch off caching for everything in
   a way that changes existing behavior.
4. The graded tree must be byte-identical to the pinned commit except for
   the **single source file where the bug lives**. Do not add, move,
   delete, rename or reformat any file; if you create scratch files to
   investigate, delete them before you finish; make no commits; do not
   modify any test file, `package.json` or metadata file. The grader
   compares every file's bytes against the pinned commit's own blobs, so
   cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `bash /app/repro.sh` (scratch files in `/tmp`,
   never inside `/app/src`).
2. **Localise**: search the tree for the glob-matcher machinery, e.g.
   `rg picomatch /app/src/packages/jest-util/src`. The conversion function
   lives in one small source file; its effect on which paths match should
   be evident from the code and from what its callers use it for (test
   selection, include/exclude filtering, transform/coverage decisions).
3. **Find the existing tests**: there is a `__tests__` directory next to
   the implementation under `packages/jest-util/src/`. Its test file for
   this behavior compares the implementation against `micromatch`:
   ```bash
   bash /app/run-test.sh /app/src/packages/jest-util/src/__tests__/globsToMatcher.test.ts
   ```
   These pass on the buggy tree — the existing cases never vary the
   options across calls, which is the only way the staleness shows.
4. **Understand the mechanism**: the function keeps a module-level map
   from glob string to compiled matcher, and consults it before compiling
   a new matcher. The options argument is not part of that decision, so
   whichever options (or absence of options) won the first race for a
   given glob keep applying forever.
5. **Fix** with the smallest possible change in that one file so that
   per-call options always build a fresh matcher while calls without
   options keep the benefit of the cache (and keep the existing default of
   dotfile matching on). Then re-run `/app/repro.sh` — it must print
   `true false` and exit 0 — and the project's own test file for the
   behavior, which must still pass.
6. **Prove nothing else broke**: run a couple of neighbouring `jest-util`
   tests of your choice with `bash /app/run-test.sh`.
7. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the clone
  still contains exactly that one commit, and that every tracked file
  except the single source file where the bug lives is byte-identical to
  that commit (any other modification, added file or untracked scratch
  file fails);
- require `/app/summary.md` to exist, be non-empty, and describe the bug;
- run `/app/repro.sh` — it must print `true false` and exit 0;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — the upstream extension of the tree's own test
  file for this behavior, adding the option-aware cases; 10 tests in
  total) over the tree's test file and run it against **your** edited
  tree sources with jest: all 10 must pass;
- run two of the project's own existing `jest-util` test files
  (`isPromise`, `formatTime`) against your tree — they must stay green;
- run authored hidden cases that reach the same code path from globs and
  options the upstream regression test does not use (a `dot` flip in the
  opposite order, `nocase` flips on differently-cased inputs, and an
  interleaving of `{dot: undefined}`, `{dot: false}` and option-less calls
  on one glob).

Reward is binary: 1 if and only if all of the above hold, otherwise 0.