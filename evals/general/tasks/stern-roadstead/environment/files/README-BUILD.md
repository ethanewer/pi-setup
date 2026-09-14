# Working inside the jest monorepo (build notes)

The repository at `/app/src` is jest, pinned at a single (parent) commit, with
everything already built offline. Quick references:

## Run the project's own unit tests (TypeScript transformed on the fly)

```bash
cd /app/src
node ./packages/jest-cli/bin/jest.js packages/jest-each/src/__tests__/ --runInBand
# or: yarn jest packages/jest-each/src/__tests__/

# a single file:
node ./packages/jest-cli/bin/jest.js packages/jest-each/src/__tests__/template.test.ts --runInBand
```

Runs take ~1-2 seconds. The snapshot-based tests need color output to match
their stored snapshots, so if you see bulk snapshot failures, run with
`FORCE_COLOR=1` (set it once: `export FORCE_COLOR=1`).

## Rebuild the compiled packages (only needed if your script reads `build/`)

```bash
cd /app/src && yarn build:js        # ~5 seconds, offline
```

## Use the built package from plain node

```js
const each = require('/app/src/packages/jest-each').default;
```

`each.withGlobal(globalShim)(tableOrRows).test('title', fn)` drives the
library; a global shim only needs `test`, `it`, `describe`, `fit`, `xit`,
`xtest`, `fdescribe`, `xdescribe` functions (with `.only`/`.skip`/`.concurrent`
properties).

## Constraints

- No network: do not run `yarn add`, `npm install`, `git fetch`, etc.
- 1 vCPU: no parallel builds.
- Scratch files in `/tmp`, never inside `/app/src` — the grader compares every
  tracked file's bytes against the pinned commit and rejects untracked files
  too.
- The tree is a shallow detached checkout: do not commit or fetch.
- `cpus = 1` and the tip of the task: fix the mechanism, not a single input.