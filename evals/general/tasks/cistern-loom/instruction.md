# cistern: migrate the repository back to strict typing

`/app/cistern/` is a self-contained TypeScript library (no runtime
dependencies; typescript and vitest are pinned devDependencies, already
installed in `/app/cistern/node_modules`) for water-distribution modelling
and billing: raw telemetry records, meter ledgers, tiered tariffs, flow
balancing, leak detection, reports and an end-to-end reconcile pipeline.

The repository ships with a real, intact git history (10 commits; see
`git log`) and a fully green vitest suite. **`tsconfig.json` currently has
strict mode disabled** — a recent refactor rewrote the legacy importers
without type annotations and switched `"strict": false` while doing so.
The strictness has never been re-enabled, so the tree type-checks only in
the relaxed mode.

Your job: **migrate the entire repository to strict typing** the way a
real migration is done — turn the strictness back on and repair every
module so the whole tree compiles, without any safety hatch. This is a
"restore the type system" task, not a "fix one bug" task.

## Environment

- Node 22, npm, git and Python 3.11 are installed. There is **no network
  access**; everything you need is on disk (including `node_modules`).
- Run the compiler with `./node_modules/.bin/tsc --noEmit -p tsconfig.json`
  from `/app/cistern/`, and the tests with `./node_modules/.bin/vitest run`
  (or `npm run typecheck` / `npm test`).
- The git history is the intended reference: `git log`, `git diff` and
  `git show` show how the tree evolved. Do **not** rewrite, squash,
  re-init or delete that history.

## The migration

1. **`tsconfig.json` (deliverable #1)**. Enable `"strict": true` and
   `"strictNullChecks": true`. Do not leave any strictness option
   explicitly disabled: `noImplicitAny`, `noUncheckedIndexedAccess`,
   `exactOptionalPropertyTypes` and `noImplicitOverride` must not appear
   as `false` in the delivered config. The verifier re-checks the whole
   tree with `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes` and
   `noImplicitOverride` forced on **on top of** whatever the delivered
   config says, so hardening must survive in the code itself.
2. **Migrate the code** so that, with strict mode on:

   ```
   ./node_modules/.bin/tsc --noEmit -p tsconfig
   ```
   exits 0 **with none of the escape hatches below**, and the same holds
   under the hardened overlay (every array/record subscript proven safe,
   every optional property read exact, every override keyworded).
3. **Do not change behaviour.** The vitest suite in `tests/` is the
   specification and may not be added to, modified, renamed or deleted
   in any way — the verifier compares every `tests/*.test.ts`
   byte-for-byte against pristine copies, and any test file that was not
   shipped counts as a violation. The exported public API of every module must keep its
   exact types: do not widen results to `| undefined` where the
   implementation is definite (for example a field that is `string | null`
   must stay exactly `string | null`), do not relax generic constraints,
   and do not weaken the exact type-level contracts consumers rely on.
4. **Repository scale.** Do not shrink the tree: it must stay above 5000
   TypeScript lines across `src/` and `tests/`, and its git history must
   stay in place.

### Banned escape hatches (checked across the whole `src/` and `tests/`)

- the `any` type, anywhere (including `as any`);
- casts through `unknown` (`as unknown`, `as unknown as T`);
- `@ts-ignore`, `@ts-nocheck`, `@ts-expect-error`.

These are checked by an AST-level scanner: `any` inside a comment or a
string does not trip it, but any *use* of `any` as a type does. The
migration must be made of real annotations, unions, narrowing and
non-null proofs — not of hatches.

## Deliverables

1. `/app/cistern/tsconfig.json` — strict, with `strictNullChecks` on and
   no disabled strictness overrides (see above).
2. `/app/cistern/package.json` — the repository manifest, unchanged in
   content (you are not asked to touch it; it is listed because the
   verifier executes the repository through it).

## Grading

The verifier:

- checks both deliverables exist, the git history has at least 10 commits
  and the tree still has 5000+ TypeScript lines;
- checks `tests/*.test.ts` are byte-identical to pristine references;
- parses the delivered `tsconfig.json` and requires `strict: true` +
  `strictNullChecks: true` with no strictness flag left `false`;
- runs the AST escape-hatch scanner over `src/` and `tests/`;
- runs `tsc --noEmit` with the delivered config and with the hardened
  overlay (strict + `noUncheckedIndexedAccess` + `exactOptionalPropertyTypes`
  + `noImplicitOverride` over `src/` **and** `tests/`);
- runs `vitest run` and requires every test to pass;
- drops two fresh **hidden type-contract files** into the tree and
  recompiles both passes — those files only compile if the migration is
  real and precise.

Every stage must pass. There is no partial credit: the reward is 1 only
when the migrated tree is strict-clean, hardened-clean, suite-green and
preserves the tree's scale, history, tests and exact exported types.