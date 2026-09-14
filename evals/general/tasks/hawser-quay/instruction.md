# A crash in parameterised test titles

This is a debugging task against a real upstream codebase. `/app/src` is a
working checkout of the **Jest** monorepo, pinned at one specific commit, with
its git metadata intact (a shallow, single-commit history). A regression lives
somewhere in it. You must reproduce it yourself, localise it, repair the
library source, and hand back a failing reproduction plus a diagnosis.

## The bug report (as filed by a user)

> A test file that uses parameterised tests crashes the whole run:

```
TypeError: Do not know how to serialize a BigInt
```

> It happens whenever the title template of an `it.each` / `test.each` block
> contains the JSON placeholder `%j` and any row value is a `bigint`. One `1n`
> anywhere in the table is enough; the entire suite fails instead of running.
> A second, related annoyance: titles whose values contain the characters
> `$&`, `` $` ``, `$'` or `$$` come out scrambled — characters are duplicated
> or moved — even though no crash occurs.

## The expected behaviour (the contract your fix must meet)

A parameterised title is built by substituting each row value into the title
template. Placeholders are the classic printf-style `%s` plus two special ones:
`%j` (JSON form of the value) and `%p` (pretty form). The contract:

1. `%j` must render the JSON serialisation of the value. A `bigint` row value
   must **not** crash; it must render as its JavaScript literal form, e.g.
   `1n`, which inside a JSON string reads `"1n"` — the same readable form
   `%s` already produces outside a JSON string. Note `%s`/`%p` with bigints
   already work; do not break them.
2. `%j` (and `%p`) must render **cyclic** values as `[Circular]` instead of
   failing or overflowing.
3. Values containing the replacement patterns `$&`, `` $` ``, `$'` or `$$`
   must appear **literally** in the rendered title — what you write in the
   table is exactly what you see in the title.

## Environment

- `/app/src` is the real Jest tree at the pinned commit (version ~30.4/30.5,
  Node 22 runtime). It contains every package, and **its test files are not
  the target**: you may read them freely, but the fix must live in the
  library source, not in tests.
- Node 22.23.2 and npm are on `PATH`. A standalone TypeScript toolchain is
  preinstalled at `/opt/jest-deps` with exact pins: `typescript`,
  `@types/node`, `@jest/get-type` 30.5.0, `pretty-format` 30.5.1 and
  `@jest/types` 30.5.1 (`tsc` is at
  `/opt/jest-deps/node_modules/.bin/tsc`).
- Parameterised-test title formatting is implemented by a **small,
  self-contained module** – a pair of `.ts` files with only those runtime
  dependencies. You do **not** need a full monorepo build (a
  `yarn install && yarn build` takes many minutes at one CPU and is
  unnecessary). To iterate fast: copy the two files of that module into a
  scratch directory, symlink
  `node_modules -> /opt/jest-deps/node_modules` next to them, and run tsc
  (CommonJS output, `es2022`, `esModuleInterop`, `skipLibCheck`): the emitted
  module's default export builds the `{title, arguments}` list for a
  `(titleTemplate, table)` call, exactly like the real code path. To find the
  module, grep the tree for the placeholder machinery (`%j`, `%p`) and the
  title-formatting helpers.
- There is **no guaranteed network** in this container and no caching proxy;
  do not attempt to download anything. Everything needed is already on disk.

## What to do

1. **Write your own reproduction first** – this is a deliverable, and it must
   genuinely fail while the bug is present. Create `/app/reproduce.sh`, an
   executable shell script with this contract:

   - It takes the path to a directory holding the **compiled formatter
     module** (the table formatter's emitted `.js` file with the name it
     already has in the source tree, plus the small helper's emitted `.js`
     next to it) as its first positional argument.
   - It loads that module's default export, drives it with a parameterised
     table whose title template uses `%j` and whose row values include a
     `bigint`, and **asserts** that the rendered titles match the contract
     above (bigint rendered as a literal like `1n`, no crash, correct JSON).
   - It prints the rendered title for the `%j`-with-bigint row to stdout.
   - It exits `0` when the rendering is correct, and **non-zero when the
     formatter crashes or renders a wrong title**.

   Concretely: before you touch any source, compile the *untouched* formatter
   module once (the state of the tree exactly as delivered) and check that
   running `/app/reproduce.sh` against that compiled module exits non-zero.
   That failing state is the bug you are about to fix.

2. **Localise and fix the root cause** inside `/app/src`. You are handed a
   symptom, not a file. The crash message and the placeholder names are your
   map; the monorepo's own source is the place to grep. Repair the library
   source so the full contract holds. Do **not** add a wrapper or
   post-processor that special-cases the exact table values from your
   reproduction – the verifier will exercise the code path with inputs you
   never saw.

3. **Write `/app/diagnosis.md`** – a short root-cause note (a few sentences)
   stating, in your own words: which module implements the title formatting,
   what exactly went wrong (why `%j` threw on bigints, why the `$&`-style
   values scrambled), and the minimal change you applied.

4. **Verify.** Recompile the module from your repaired tree and check:
   - `/app/reproduce.sh <compiled-repaired-module>` exits `0` and prints the
     correct title;
   - the same reproduction still fails against the *untouched* compiled
     module (keep one of those scratch compiles around for the comparison,
     or re-derive it from git);
   - `%s`, `%p` and plain titles still render as before (nothing else broke).

## Deliverables and success criteria

Everything below is checked automatically; the reward is binary (1 or 0):

1. `/app/reproduce.sh` – executable, satisfies the argument contract, fails
   against the pre-fix formatter and passes against the repaired one.
2. `/app/diagnosis.md` – present, identifies the real module and cause.
3. The repaired source in `/app/src` – the verifier compiles the module from
   **your edited tree** and runs the project's own regression tests for this
   bug against it, plus additional hidden cases with fresh inputs.

## Constraints

- Do not modify anything under `/opt` (you should not need to; the verifier
  re-checks its reference material from read-only sources, so tampering with
  `/opt` or any verifier material will not help you pass).
- Do not rename, delete or restructure the formatter module's files in a way
  that breaks the standalone compile.
- No network. No git operations that rewrite history (there is only one
  commit anyway).
- Time budget is generous; the expensive part is finding and understanding
  the defect, not running the checks.