# capstan-mooring

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

One of the built-in rules reports numeric literals that would lose precision
when JavaScript converts them to its `Number` type, e.g.:

```
This number literal will lose precision at runtime.
```

Literals written with a trailing decimal point and no fractional digits are
not handled: code like `var x = 0.` is reported even though the value is
exactly representable — the same number written as `0` or `0.0` is accepted.
The message is confusing here because `0.` is exact. Genuinely lossy
literals in the same shape, such as `var x = 9007199254740993.`, must
continue to be reported.

Reproduce it:

```bash
cd /app/src
node /app/repro.js
```

On this tree the script exits 1 with `Should have no errors but had 1`
(the valid case `var x = 0.` is falsely flagged with messageId
`noLossOfPrecision`). The correct behaviour is to exit 0 with no errors.

## Requirements

1. Fix the tree so that `/app/repro.js` exits 0 with no errors, while
   preserving the rule's behaviour everywhere else:
   - plain spellings (`0`, `0.0`, `-0`, `1e3`, ...) behave exactly as
     before — a literal that is exactly representable stays valid and a
     genuinely lossy one stays an error;
   - a trailing-dot literal whose value is exact (`0.`, `10.`, `3.`, ...)
     is no longer reported, wherever it appears;
   - a trailing-dot literal whose value is **not** exactly representable
     (`var x = 9007199254740993.`) is still reported with messageId
     `noLossOfPrecision`;
   - the rule's own test file (`tests/lib/rules/no-loss-of-precision.js`,
     run with `node_modules/.bin/mocha`) keeps passing as shipped and also
     passes the upstream version of that file that the grader plants (see
     Grading).
2. Fix the *cause*, not the symptom: the raw source text of the literal
   (which for `0.` still contains the trailing `.`) must be normalised to
   the same form it is compared against, exactly as the plain spellings
   are. Do not simply whitelist the specific snippet `var x = 0.` and do
   not disable the rule.
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
   (`node_modules/.bin/mocha tests/lib/rules/no-loss-of-precision.js`), then
   read the rule source under `lib/rules/`. The rule reads each literal's
   raw source text, converts it to scientific notation, and compares that
   against the parsed value. Notice that a trailing `.` in the raw text
   changes how that conversion strips digits for literals like `0.`, while
   the parsed value has no dot to compare against.
3. **Fix** with the smallest possible change in that one file: a literal
   whose raw text ends in `.` must be treated as if that final dot were not
   there — nothing else may change, so genuine losses like
   `9007199254740993.` are still detected.
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
  which this tree predates) over `tests/lib/rules/no-loss-of-precision.js`
  and run it with mocha: all 131 cases must pass;
- run a targeted selection of the project's existing rule and rule-tester
  tests, which must stay green;
- run authored hidden cases that reach the same code path from inputs the
  upstream test does not use (trailing-dot literals in other syntactic
  positions, unary-minus and numeric-separator shapes, and still-lossy
  trailing-dot forms), via the project's own RuleTester.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.