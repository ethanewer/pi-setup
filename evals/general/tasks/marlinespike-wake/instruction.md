# marlinespike-wake: SCSS `@if` conditions are line-broken in the wrong place

You are working inside a real open-source codebase: **Prettier**
(`prettier/prettier`), the opinionated code formatter, checked out at a pinned
commit in `/app/src` (a shallow, detached clone with a clean working tree).
There is a bug in this tree's SCSS formatting. Your job is to find it, fix it
in the working tree, and prove the fix with the project's own test tooling and
with a reproduction of your own that you write first. You are deliberately
**not** told which file or function to change: localising the bug is part of
the task.

## Environment

- Node.js 22 and npm are installed and on `PATH`. The repository's
  dependencies (`node_modules/`) are already installed at this commit — do
  **not** run `npm install` or `npm update`, and do not modify
  `node_modules`.
- **There is no network** in this container. Everything needed is already in
  the image. The project's own test runner is available as
  `node_modules/.bin/jest` and works offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds or test runs.
- The tree at `/app/src` is a shallow one-commit clone in detached HEAD state.
  Do not commit, fetch, rebase, or otherwise modify the repository history or
  the `node_modules` directory.
- Do **not** edit anything under `tests/` (the snapshot fixtures and test
  scripts are used as-is by the grader), and do not add or delete tracked
  files. Your fix must be confined to the project's own source code.

## The bug (user-visible symptom)

Users report that when an SCSS control-directive condition — `@if`, `@else
if`, or `@while` — combines *several comparisons* with the logical keywords
`and`, `or`, or `not`, Prettier wraps the condition in the wrong place. Here
is how it currently comes out:

```
@if $total-items-count ==
  0 and
  $is-active-flag ==
  0
{
}
```

Notice what happened: the line breaks land **immediately after the comparison
operator** (`==`), stranding the operator alone at the end of the line and
pushing its right-hand operand onto the next line. The same misplacement
happens with `!=` and with the relational operators `<`, `>`, `<=`, `>=`. The
condition is still readable, but the break placement is inconsistent with how
Prettier formats the same comparisons everywhere else.

The correct behaviour is to keep each comparison together as a unit — the
comparison operator stays on the same line as its right-hand operand — and
break **before** the next comparison instead. The desired output for the same
condition is:

```
@if $total-items-count == 0 and
  $is-active-flag == 0
{
}
```

Concretely: whenever an SCSS control directive chains comparisons with
`and`/`or`/`not`, a comparison like `$a == 0` (or `$a != 0`, `$a < 0`, ...)
must never be split by a line break between the operator and its operand, no
matter how long the operands are or how many comparisons the condition chains.
The break that makes the condition fit should fall between the logical
keyword and the next comparison. Conditions with a *single* comparison are
unaffected. Prettier's own line width (`printWidth`, default 80) and its
other SCSS formatting rules remain as they are.

If a condition already fits on one line, it must be left exactly as Prettier
already prints it — only the line-break placement for conditions that do not
fit is wrong.

## Reproduce it yourself

Because the symptom is about long operands overflowing the print width, you
can trigger it with files like this (write several variants yourself):

```scss
@if $some-very-long-variable-name == 0 and $another-very-long-variable-name == 0 {}
```

and format them with the project's own CLI:

```bash
cd /app/src
node bin/prettier.js /path/to/input.scss
```

## Deliverables

1. **The fixed tree at `/app/src`.** Edit the project's source so the CLI
   formats the affected conditions correctly. The tree must still be exactly
   the pinned commit with the same tracked files, except for the source change
   that implements the fix.

2. **`/app/summary.md`** — a change summary. It must state what was wrong
   (the observable symptom), where in the code the wrong decision was made
   (file and the relevant piece of logic), what you changed, and how you
   verified the fix.

3. **`/app/repro/`** — your own failing reproduction, written **before** you
   fix anything, with exactly these files:

   - `input.scss` — an SCSS snippet that triggers the bug on the unfixed tree
     (a control-directive condition that chains long comparisons and must
     wrap).
   - `expected.scss` — the *correct* formatting of `input.scss`, i.e. exactly
     what `node bin/prettier.js input.scss` must print after the fix, byte
     for byte.
   - `check.sh` — an executable shell script that proves the fix. Its contract:
     `cd /app/src`, run `node bin/prettier.js /app/repro/input.scss`, compare
     the stdout with `/app/repro/expected.scss`, and exit `0` iff they are
     byte-identical. It must exit non-zero (with a readable diff) when the
     outputs differ. It must do its work by running the project's own CLI —
     not by inspecting the source tree's git state.

   The grader runs your `check.sh` twice: once against the pristine pre-fix
   tree (your reproduction must **fail** there, proving it really targets this
   bug) and once against your repaired tree (it must **pass**). Do not leave
   `expected.scss` identical to `input.scss` — a reproduction that asserts a
   no-op cannot demonstrate the bug.

## Verification you should run before finishing

The project's own jest-based format tests run offline in seconds. These are
the suites the grader will run against your repaired tree, so make them pass:

```bash
cd /app/src
node_modules/.bin/jest tests/format/scss/atrule/format.test.js --runInBand --ci
node_modules/.bin/jest tests/format/scss tests/format/css --runInBand --ci
```

Note that the grader replaces the SCSS `@if` fixtures under
`tests/format/scss/atrule/` with the project's own regression fixtures for
this bug before running them, and it will also run several additional SCSS
conditions of its own through the CLI. Your fix must therefore be a real
general fix for the break-placement rule, not a special case for one
specific variable name.

## Constraints recap

- Only the project's own source files may be changed inside `/app/src`; the
  repository history, index, and `node_modules` must stay untouched.
- `cpus = 1`; no network; no fetching anything.
- Do not modify `tests/`, `scripts/`, `package.json`, or the snapshot files.
- The bug is in the tree you were given — do not go looking for a newer
  version of the code anywhere else; there is none to find.