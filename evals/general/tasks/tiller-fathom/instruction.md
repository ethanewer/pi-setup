# Prettier drops the quotes from a method named `new`

You are debugging a real bug in the **Prettier** formatter (JavaScript /
TypeScript). A checkout of the `prettier/prettier` source tree is at
`/app/src` with its dependencies already installed (`npm install` has been
run; Node 22 and jest are available). The checkout sits on branch `work` at a
single real commit that contains the bug. `/app/pristine` is a second, frozen,
identical checkout that you must **not** modify — the grader uses it as the
pre-fix reference. There is **no network access** during the trial: everything
you need is already on disk.

## The reported bug

When Prettier formats TypeScript code, a method member that is literally named
`new` and written **with quotes** inside an `interface` or inside an object /
`type` literal —

```ts
interface Container {
  "new"(id: string): number;
}
```

— is reprinted **without quotes**:

```ts
interface Container {
  new(id: string): number;
}
```

That changes the meaning of the user's code: in TypeScript, an unquoted
`new(...)` member in an `interface` or in a `type` alias is a *construct
signature* (it describes how instances are built), not a method named `new`.
Prettier must keep the quotes on a quoted method named `new` (single or double
quotes). Every other kind of member and every other name must keep formatting
exactly as it is today — in particular, names that the normal quote rules
would still unquote because they are safe identifiers must still be unquoted.

## Your task

1. **Reproduce it first.** Write your own TypeScript reproduction and save it
   to `/app/repro/repro.ts`. It must be a file Prettier can format as
   TypeScript and it must provoke the defect: include at least one `interface`
   or `type` literal with a quoted method named `new` (single or double
   quotes, or both), alongside at least one ordinary member. Then run the
   project's own formatter on it:

   ```
   node /app/src/bin/prettier.js /app/repro/repro.ts
   ```

   The formatted source is printed to stdout. Run this against the
   **unmodified** checkout, capture its output, and save it to
   `/app/repro/before.txt`. If `before.txt` does not show the quotes being
   dropped (i.e. Prettier keeps the quotes on `new`), your reproduction does
   not exhibit the defect — adjust it until it does.

2. **Fix the formatter** so that formatting your reproduction preserves the
   quotes on the `new` method while changing nothing else. The fix must live
   in the formatter itself, under `/app/src`. Do **not** patch around the
   symptom: no editing or regenerating of test files or snapshots
   (`jest --updateSnapshot` is forbidden), no hard-coding of input files, no
   wrapping or post-processing of the CLI. After your fix, run the formatter
   on your reproduction once more and save the output to
   `/app/repro/out.txt`. In `out.txt` the method must still carry its quotes.

3. **Verify with the project's own test suite.** Prettier's formatting
   regression tests live under `/app/src/tests/format`. Run the quote-props
   suite, which is the project's own test area for this behaviour:

   ```
   cd /app/src && node_modules/.bin/jest --ci --runInBand tests/format/typescript/quote-props
   ```

   It must pass completely. On the unfixed tree exactly two of its tests fail
   (the regression fixtures for this bug, under the two quote-props modes
   that would unquote); with your fix all of them must pass. Then run a
   broader span of the project's own formatting tests:

   ```
   cd /app/src && node_modules/.bin/jest --ci --runInBand tests/format/typescript
   ```

   All of `tests/format/typescript` must pass. If your change alters how any
   other TypeScript code is formatted, you have regressed something the
   project tests — reconsider.

## Deliverables

All three must exist when you are done:

- `/app/repro/repro.ts` — your TypeScript reproduction of the defect
- `/app/repro/before.txt` — output of the formatter on `repro.ts` from the
  untouched, buggy checkout (must show the quotes being dropped)
- `/app/repro/out.txt` — output of the formatter on `repro.ts` after your fix
  (must keep the quotes on the `new` method)

## Notes

- `node /app/src/bin/prettier.js <file.ts>` formats one file to stdout. The
  parser is chosen from the file extension; no configuration file is present
  for TypeScript files, so the defaults apply (`quoteProps` is `as-needed`).
- Do not modify `/app/pristine` or anything under `/app/src/tests` — the
  project's tests must pass unmodified.
- Committing your work on branch `work` is fine but not required; the grader
  reads the working tree.