# capstan-inlet

You are working inside the real upstream open-source repository
**aquasecurity/trivy**, a vulnerability scanner for containers and
dependencies, checked out at a pinned commit in `/app/src` (the working
tree starts clean). There is a bug in the parser that reads the .NET SDK's
`*.deps.json` dependency-graph files. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You are
intentionally **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- Go 1.26.3 is installed at `/opt/go/bin/go` and on `PATH`; `git` is
  available. The repository's `go.mod` (`go 1.26.3`) and the committed
  `go.sum` pin the toolchain and every transitive module dependency.
- Outbound network is not available and must not be relied on. Everything
  needed is baked in: the module cache (`/opt/gomodcache`) holds every
  pinned dependency, and the compile cache (`/opt/gocache`) is warm, so any
  `go test` you run completes offline, usually in well under a minute.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit, detached). Do not commit,
  fetch, or otherwise modify `.git`.
- Run the .NET dependency parser's own test suite with:

  ```bash
  cd /app/src
  go test -v -short ./pkg/dependency/parser/dotnet/core_deps/
  ```

  All tests in it pass at the pinned commit; this is your fast localisation
  loop. `environment/files/README-BUILD.md` has further build notes.

## The bug (user-visible symptom)

When a .NET application's dependency graph file contains **several sibling
projects** — typical for solutions where the root application and a number
of helper projects are all recorded as `libraries`, so that only the
reference graph distinguishes them — the scanner treats the **first-listed
project** as the root application. Every other project and its transitive
dependencies are silently omitted from the reported packages: the report
contains only the first project plus whatever ends up reachable from it.

The root application is not the first project in the file. It is the
project that **no other library references**: in these files each project
appears as a library of `type: "project"`, and a helper project is always
referenced by name and version in the `targets` dependency edges of the
libraries that use it. The project nobody references is the application.

Reproduce it:

```bash
cd /app/src && /app/reproduce.sh
```

The script builds a small four-library workspace (three sibling projects and
one third-party package, with the application project listed *after* the
helpers) and runs the project's own test command against it. While the bug
is present this exits non-zero and prints `expected: 4` vs `actual: 2` (and
the two missing helper-project IDs) — the helpers listed before the
application are silently missing. When the tree is fixed it prints a green
`PASS`.

## What to do

1. Observe the failing behaviour with `/app/reproduce.sh`.
2. Localise the defect inside the .NET dependency parser under
   `pkg/dependency/parser/dotnet/`. The package's own test suite is the
   fast, targeted way to pinpoint it: run only
   `go test -v -short ./pkg/dependency/parser/dotnet/core_deps/`, never the
   whole trivy suite (that would take far too long at one CPU).
3. Fix the cause in the library source. The root project must be identified
   from the reference graph, not from the file's library order, and when the
   graph does not identify exactly one root the parser must not guess. Do
   **not** modify any test files, do **not** add post-processing or a
   wrapper that papers over the wrong output, and do **not** special-case
   particular names or libraries. Repair the defect at its source, minimally.
4. Re-run `/app/reproduce.sh` and the package's whole test suite (every test
   in `core_deps` must stay green) to prove the fix.
5. Write `/app/summary.md`.

## Deliverables

1. The repaired source tree in `/app/src` (your fix applied as ordinary file
   edits to the working tree).
2. `/app/summary.md` — a non-empty write-up (at least a few sentences) that
   states, in your own words:
   - **where the defect lives** (the module and the routine),
   - **the root cause** (what the code did wrong and why single-project
     files never showed it),
   - **the fix** (the minimal change you applied and how you verified it).

Both deliverables are checked.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the object
  store holds nothing beyond it, and that every tracked file except **the
  single source file the bug lives in** is byte-identical to that commit —
  any other modification, added file, or leftover untracked scratch file
  fails the task;
- require `/app/summary.md` to exist;
- place the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` from a successor revision of the tree) and further
  hidden test cases into the `core_deps` package, and run the project's own
  test command against the result. Every test must pass, including the
  regression cases (a multi-project workspace resolved by the reference
  graph, and a file whose graph does not single out one root) and
  generalising hidden variants.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.

## Constraints

- Do not modify anything under `/tests` or `/solution` (you cannot see them
  anyway), and do not modify `/opt/golden`.
- Do not remove or rewrite the test suite of the affected package.
- If you create scratch files inside `/app/src` while investigating, delete
  them before finishing (the reproducer removes its own).
- No network: the trial runs fully offline. Everything you need is already
  in the image.
- Time budget is generous; the expensive part is finding the defect, not
  running the checks.