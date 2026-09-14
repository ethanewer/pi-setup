# stern-roadstead — working inside the jest monorepo

You are inside a real open-source codebase: **jest** (`jestjs/jest`), checked
out at a pinned commit in `/app/src`. The working tree starts clean. There is
a bug in its parameterised-test (`.each`) title interpolation. Find it, fix
it, and prove the fix with the project's own test runner. You are deliberately
not told which file or function to change: localising the bug is part of the
task.

## Environment

- Node 22 and the jest monorepo at `/app/src`, fully installed and built:
  `yarn install` and `yarn build:js` have already run, so `node_modules` is
  populated and every package has a fresh `build/` output. Anything you need
  is on disk.
- **There is no network.** Everything required is baked in. `yarn` runs
  offline; the project's test runner is
  `node ./packages/jest-cli/bin/jest.js` (or `yarn jest`) from `/app/src`,
  and it transforms TypeScript sources directly — you do not need to rebuild
  to run tests against your edits.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree is a shallow, detached checkout (one commit). Do **not** commit,
  fetch, or otherwise modify `.git`. `git` is configured so your user can read
  it.
- The image was built as root but the tree is owned by uid 1000; everything
  under `/app` is writable by you.

## The bug (user-visible symptom)

When a developer writes a table-driven test with a column heading that
contains characters special in regular expressions, the whole table fails
before any test runs. For example:

```js
test.each`
  count(*) | expected
  ${1}     | ${'one'}
  ${2}     | ${'two'}
`('rows: $count(*) is $expected', ({count, expected}) => { ... });
```

On the buggy tree this throws something like

```
SyntaxError: Invalid regular expression: /\$(count(*)|expected)[.\w]*/g: Nothing to repeat
```

before any test can run. Headings that do not crash can still be wrong: a
heading containing a dot or a vertical bar is interpreted as part of a regular
expression (a dot matches any character; a bar splits the alternatives), so
`$variable` titles interpolate the wrong value or a whole table degenerates.
Column headings should be usable **literally** inside `$variable` test titles,
no matter what characters they contain.

## Requirements

1. Write your own failing reproduction **first**, as the deliverable
   `/app/repro.sh` — see the contract below — and use it to confirm the bug is
   real on the unmodified tree, then fix the tree so the same reproduction
   passes.
2. Fix the underlying mechanism, not just one input: the same defect is
   reachable from many headings (any regex-special character, overlapping
   headings, dotted headings). The verifier tests inputs you have not seen.
3. Everything else must keep working exactly as before: ordinary headings,
   `$key` and `$key.path` interpolation, and the `$#` index placeholder must
   stay unchanged. The project's existing `jest-each` unit tests must stay
   green.
4. The graded tree must be byte-identical to the starting tree **except for
   the single source file where the defect lives** (the one named by the stack
   trace when your reproduction fails). Do not add, move, delete or rename any
   file; do not reformat anything; do not modify `package.json`, `tsconfig*`,
   lockfiles or metadata. Scratch files belong in `/tmp`, never inside
   `/app/src`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own reproduction (see contract).
3. `/app/summary.md` — a non-empty write-up: the symptom, where the defect
   was, what you changed, and how you verified it.

### `/app/repro.sh` contract

`/app/repro.sh` is an executable shell script that drives the repository's own
`.each` table machinery (through the library's code, e.g. the built package in
`/app/src` or the project's test runner — not text-grep on source files). Run
it from anywhere:

- On a tree that **still contains the bug** it must exit non-zero (the
  failure should be visible on stderr).
- On a **corrected** tree it must exit 0 and print exactly, on stdout:

```
rows: 1 is one
rows: 2 is two
```

and nothing else on stdout.

## Working loop (recommended)

1. **Reproduce**: write `/app/repro.sh`, run it, and read the failure. The
   `SyntaxError` message names the invalid regular expression, and the stack
   trace names the source file that builds it — that is your localisation
   hint. Then read that code: how are the template keys turned into the
   regex's alternation? Why does a `*` heading crash while a `.` heading
   silently interpolates the wrong value? What happens when two headings
   share a prefix?
2. **Fix** with the smallest possible change in that one file. If your repro
   reads built output, refresh it with `yarn build:js` (seconds) after
   editing source, or run the tests instead: `node ./packages/jest-cli/bin/jest.js packages/jest-each/src/__tests__/ --runInBand` (or `yarn jest ...`) transforms the TypeScript source directly.
3. **Prove nothing else broke**: run the project's own `jest-each` unit suite
   (the command above); all ~550 tests must stay green. Some of those tests
   snapshot ANSI-coloured error messages, so run with `FORCE_COLOR=1`
   (`export FORCE_COLOR=1` once, or prefix every run) — without it the
   snapshot tests report bulk colour mismatches and nothing is actually
   broken.
4. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`, run after you finish) will, on
your final tree:

- assert `HEAD` is still the pinned parent commit, and that every tracked
  file except the single defect source file is byte-identical to that commit
  (any other modification, added file or untracked scratch file fails);
- require `/app/repro.sh` and `/app/summary.md` to exist;
- run your `/app/repro.sh` on the fixed tree (must print exactly the two
  lines above and exit 0), then swap your fixed file back to the parent
  version and run it again — the reproduction must genuinely fail there, or
  your reproduction did not reproduce the bug;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`, extracted from the commit that fixed it upstream) and
  run it with the project's test runner — it must pass;
- run the project's existing `jest-each` unit suite — it must stay green;
- run hidden cases with headings different from the ones shown here — they
  exercise the same mechanism and must pass.

Be honest in `/app/summary.md`: it is read by humans.