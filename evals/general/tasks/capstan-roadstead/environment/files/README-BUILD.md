# capstan-roadstead — build notes

You are inside a real open-source repository: **jest**
(`https://github.com/jestjs/jest`), the JavaScript test framework, checked
out at the pinned commit `69b089574f10e607a93ad1b3eb56b4876e2a43fb` in
`/app/src` (detached HEAD, working tree clean). There is a bug in how
glob-based file selection treats matcher options. Find it, fix it in the
working tree, and prove the fix with the project's own test tooling.

## Environment

- Node.js 22 with npm. **No network** at trial time: `git fetch`, `curl`,
  `npm install` and downloads will not work. Do not try.
- A standalone compile/test toolchain lives at `/opt/tsapp`:
  - TypeScript 5.9.3 (`/opt/tsapp/node_modules/.bin/tsc`)
  - the published `jest` 30.4.1 test runner
    (`/opt/tsapp/node_modules/.bin/jest`)
  - runtime matcher libraries as pinned by the repository:
    `picomatch` 4.0.7 and `micromatch` 4.0.8
- `/app/repro.sh` — compile-and-run reproduction driver (see
  `instruction.md`).
- `/app/run-test.sh <file.test.ts>` — compile any test file against the
  tree sources and run it with jest.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; leave them
  alone.
- `cpus = 1`: one vCPU. No parallel builds, no parallel test runs.
- The tree at `/app/src` is shallow (one commit) and detached. Do not
  commit, fetch, add remotes, or otherwise modify `.git`. No `npm install`
  inside `/app/src` (the monorepo is not set up for it and there is no
  network anyway).

## Quick start

```bash
bash /app/repro.sh            # compile tree sources, run the 2-call repro
```

On this image the script prints `true true`, explains that the second call
(made with `{dot: false}`) matched a dotfile, and exits 1.

## Iterating

1. Find the conversion of glob pattern lists into matcher functions.
   Grep the tree, e.g. `rg picomatch /app/src/packages` — the function is
   defined in one small source file and imported from several places
   (test selection, include/exclude filtering, transform/coverage
   decisions). Read it and the code around it, and the caller sites.
2. Run the project's own existing tests for this behavior, which live in
   the tree (there is a `__tests__` directory next to the implementation
   under `packages/jest-util/src/`):
   ```bash
   bash /app/run-test.sh /app/src/packages/jest-util/src/__tests__/globsToMatcher.test.ts
   ```
   These tests compare the implementation's behavior against the
   `micromatch` package. All of them pass on the buggy tree (the bug only
   shows up when options differ across calls, which those existing tests
   do not do).
3. Edit, then re-run `/app/repro.sh` and the test file above. Scratch
   files belong in `/tmp`.
4. When the repro prints `true false` and exits 0, run the project's own
   test file again plus a few neighbouring `jest-util` tests of your
   choice to confirm nothing else moved.

## Grading contract

The verifier will, on your final tree:

- assert `HEAD` is still the pinned commit and that every tracked file
  except the **single source file where the bug lives** is byte-identical
  to that commit;
- require `/app/summary.md` to exist and describe the bug you fixed;
- run `/app/repro.sh` — must print `true false` and exit 0;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`, a 10-case extension of the tree's own test file,
  adding the option-related cases) and run it against **your** tree
  sources — all 10 must pass;
- run two of the project's own existing `jest-util` test files
  (`isPromise`, `formatTime`) against your tree — they must stay green;
- run authored hidden cases that reach the same code path from inputs the
  upstream regression test does not use.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.