# ballast-drift

You are working inside a real open-source codebase: **eslint**
(`https://github.com/eslint/eslint`), the JavaScript linter, checked out at a
pinned commit in `/app/src` (the working tree starts clean). There is a bug
in one of its built-in lint rules. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- Node.js 22 with npm is installed. The repository's full dependency set
  (runtime + dev, including mocha and espree) is already installed in
  `/app/src/node_modules`, so the whole reproduce/fix/verify loop runs
  offline.
- **Do not rely on the network.** Everything you need is baked into the
  image, the trial may have no network access, and the clone's origin remote
  has been removed — `git fetch`, `npm install` and downloads will not work.
  Do not modify `node_modules`.
- `cpus = 1`: one vCPU. Do not launch parallel builds or test runs.
- The tree at `/app/src` is shallow (a single commit) and detached at a
  pinned commit. Do not commit, fetch, or otherwise modify `.git`.
- `/app/repro.js` and `/app/README-BUILD.md` are provided; read the README.

## The bug (user-visible symptom)

One of the built-in rules can be configured, via an option, to stop checking
capitalised *property accesses*: with that option set, ordinary method calls
are supposed to be ignored, and only **bare** calls to capitalised names
(such as `Foo()`) are checked. In this tree the option does not work for
method calls whose name ends in `UTC`: with the option set, code like
`foo.UTC()`, `foo?.UTC()` (optional chaining), or `a.Date.UTC()` is still
reported as

```
A function with a name starting with an uppercase letter should only be used as a constructor.
```

Users who configure the rule to ignore property accesses get spurious errors
on ordinary member calls, and the same false positive fires on deeper chains
such as `a.Date.UTC()`.

Reproduce it:

```bash
cd /app/src
node /app/repro.js
```

On this tree the script exits 1 with `Should have no errors but had 1` (each
of the three snippets is falsely flagged with messageId `upper`). The correct
behaviour is to exit 0 with no errors.

## Requirements

1. Fix the tree so that `/app/repro.js` exits 0 with no errors, while
   preserving the rule's behaviour everywhere else:
   - with the property-checking option **on** (the default), the rule and
     its exemptions must behave exactly as before, in both directions: a
     genuine `Date.UTC(...)` call stays valid, and a non-Date member call
     like `foo.UTC()` stays an error;
   - with the option **off** (`properties: false`), a **bare** capitalised
     call like `UTC()` must still be an error — the option only exempts
     member accesses, it must not switch the whole rule off;
   - the rule's own test file (`tests/lib/rules/new-cap.js`, run with
     `node_modules/.bin/mocha`) keeps passing as shipped and also passes the
     upstream version of that file that the grader plants (see Grading).
2. Fix the *cause*, not the symptom: make the option take effect in the
   rule's decision path for all member calls. Do not simply whitelist the
   specific snippets `foo.UTC()`, `foo?.UTC()` and `a.Date.UTC()` and do not
   disable the rule for everything.
3. The graded tree must be byte-identical to the pinned commit except for
   the **single source file where the bug lives**. Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify `tests/`,
   `package.json`, `.npmrc` or any metadata file. The grader compares every
   file's bytes against the pinned commit's own blobs, so cosmetic
   side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `node /app/repro.js` (scratch files in `/tmp`, never
   inside `/app/src`).
2. **Localise** the bug: run the rule's own tests
   (`node_modules/.bin/mocha tests/lib/rules/new-cap.js`), then read the
   rule source under `lib/rules/`. Find where a capitalised callee decides
   whether it is allowed, and trace how the "skip property accesses" option
   is meant to short-circuit that decision — notice that it only kicks in
   *after* a special case that handles callees named exactly `UTC`
   (allowing only `Date.UTC`), so that special case runs even when the
   option says not to check properties at all.
3. **Fix** with the smallest possible change in that one file: the option
   must be honoured before/inside the member-expression handling, so every
   member callee is exempted when the option is set, while the `Date.UTC`
   exemption (and the error for non-Date `UTC` calls when the option is
   not set) is preserved.
4. **Prove nothing else broke**: re-run `/app/repro.js` (must exit 0), the
   rule's own test file, and a few neighbouring rule tests of your choice —
   they pass on the pristine tree and must still pass after your fix.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails);
- require `/app/summary.md` to exist and be non-empty;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — the upstream version of the rule's test file,
  which this tree predates) over `tests/lib/rules/new-cap.js` and run it
  with mocha: all 97 cases must pass;
- run a targeted selection of the project's existing rule and rule-tester
  tests, which must stay green;
- run authored hidden cases that reach the same code path from inputs the
  upstream test does not use (deeper member chains, computed member access,
  and value-preservation checks), via the project's own RuleTester.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.