# Fix a Markdown formatting bug in Prettier

## Environment

- `/app/src` is a git checkout of **Prettier** (the opinionated code
  formatter, `prettier/prettier`) at a pinned upstream revision from before
  this bug was fixed. It is a real upstream tree, exactly as the project
  ships it: `src/`, `tests/`, everything is the project's own code,
  unchanged. The bug is still present in this tree.
- All runtime and test dependencies are already installed under
  `/app/src/node_modules` (`npm install` ran at image build time). The test
  runner is `/app/src/node_modules/.bin/jest`. There is **no network** in
  this container: do not run `npm install`, `npm update`, `git fetch`, or
  any download. Everything you need is on disk. `node --version` is 22.x.

## The bug

A user reports that formatting a Markdown file corrupts it. The file uses a
*setext heading* — one or more text lines followed by a line of `=` or `-`
characters — written inside a blockquote, where every source line of the
heading starts with its own blockquote marker (`>`). Running Prettier on
such a file collapses the heading's continuation lines onto the first line
and prints the blockquote markers inline, between the words:

```md
> Multi
> Line
> ===
```

becomes

```md
> Multi > Line
> ===
```

For a heading that spans three text lines it becomes `> Multi > Line >
Three`. The reformatted file no longer means the same thing as the input:
it is no longer a setext heading with three short text lines but one long
line with literal `>` characters in the middle of it.

Your job: reproduce the failure, find the cause inside the Prettier source
at `/app/src`, and fix the formatter so each line of a setext heading
written inside a blockquote keeps its own blockquote marker.

## Steps

1. Reproduce:

   ```
   cd /app/src && node bin/prettier.js /app/reproduce.md
   ```

   Today it prints the corrupted form `> Multi > Line` followed by `> ===`.

2. Localise the cause in `/app/src` and make the minimal source change that
   fixes it.

3. Verify your fix:

   ```
   cd /app/src && node bin/prettier.js /app/reproduce.md
   ```

   must print the file back unchanged:

   ```
   > Multi
   > Line
   > ===
   ```

## Acceptance criteria (what will be checked)

1. `node bin/prettier.js /app/reproduce.md` prints the input file back
   byte-for-byte unchanged.
2. The project's own Markdown format test suite passes, run with the
   project's own runner from `/app/src`:

   ```
   ./node_modules/.bin/jest tests/format/markdown --config jest.config.js --runInBand
   ```

   That suite includes the regression tests for this exact bug (the
   benchmark supplies them during grading); expect it to take only a few
   seconds. Run it yourself while you work and leave it green.
3. Any setext heading written inside a blockquote keeps one `> ` marker per
   source line after formatting — whether the heading spans two, three or
   more text lines, uses a `=` or a `-` underline, is nested two levels deep
   (`> >`), or includes very long text lines. Other blockquote content that
   is not a setext heading keeps its current formatting.
4. The tree is otherwise untouched: the only file that may differ from the
   pinned upstream revision is the single source file your fix changes. Do
   not modify or add upstream tests, do not add scratch files (the benchmark
   supplies its own regression tests during grading). The fix may be left
   committed or uncommitted in the working tree.

## Deliverable

The repaired Prettier tree at **`/app/src`**.