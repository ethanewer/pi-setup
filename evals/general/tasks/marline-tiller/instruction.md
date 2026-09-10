# marline-tiller: repair the marline-lib component library

`/app` is a git worktree of **marline-lib**, a small React component library.
It contains three form controls — `Counter`, `QuantityInput` and `TagPicker`,
exported from `src/index.ts` — plus their vitest suite under `tests/`, build
tooling (`package.json` scripts, vite and tsconfig files), a README that
documents the full component API, and a complete git history.

Your job is to bring the library back to a shippable state. Two things are
currently wrong with it, and both are scored independently. **The README
(`/app/README.md`) is the normative specification for how the components must
behave** — behaviour below is defined by it, not by this file.

## Environment

- Node.js 22 and npm are installed. All dependencies are already installed in
  `/app/node_modules` (the container has no network; do not run `npm install`).
- The worktree has a git history — `git log`, `git diff` and friends are
  available and are part of the debugging material you are expected to use.
- Do not modify anything under `/app/node_modules`. Everything else under
  `/app` is fair game.

## Requirement 1 — the test suite must be green

The repository ships a test suite run with:

```
cd /app && npm test
```

(vitest + jsdom + @testing-library/react). The suite encodes the behaviour
documented in the README, and it is currently **red**: failing tests span the
three component specs and the build contract spec. When your fix is complete,
`npm test` exits 0 with every test green.

The grader does **not** rely on this suite to score you — it runs its own
independent fixture battery against the *built* library, so making the repo's
own tests pass by weakening or deleting them cannot earn credit. Treat the
suite's failing assertions as the precise description of what is broken and fix
the library.

## Requirement 2 — the packaging contract

`npm run build` must exit 0, and its output in `/app/dist` must satisfy the
library's consumption contract:

- an **ESM artifact** at `/app/dist/marline-lib.mjs` — a real ES module
  (uses `export`, not `module.exports`) that exports `Counter`,
  `QuantityInput` and `TagPicker`;
- **type declarations** under `/app/dist` (`.d.ts` files) covering every
  public export of the library, at minimum `dist/index.d.ts` declaring the
  three components.

Today `npm run build` exits 0 but `/app/dist` contains no ESM artifact and no
declarations, so consumers cannot import the library and TypeScript consumers
get no types. `/app/package.json` is the entry point for both scripts
(`build`, `test`, `typecheck`); you are free to adjust the tooling under
`/app` until the contract holds.

## Deliverables

- `/app/package.json` — the build entry whose scripts must work.
- `/app/dist` — the validated build output (produced by `npm run build`).

## Success criteria

1. `cd /app && npm test` → exit 0, all green.
2. `cd /app && npm run build` → exit 0, `/app/dist/marline-lib.mjs` present as
   ESM, and `.d.ts` declarations present for every exported component.
3. The three components behave as the README documents — controlled mode
   mirrors the caller-owned value, uncontrolled mode owns its state, every
   `onChange` reports exactly what happened, arrows and steps clamp to
   `[min, max]`, invalid input commits nothing, and the caller's prop arrays
   are never mutated.

There is no separate answer file to produce: the deliverable is the repaired
repository itself, verified by rebuilding it from scratch.
