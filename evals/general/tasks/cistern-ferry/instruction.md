# Fix an HTML attribute-casing bug in Prettier

## Environment

- `/app/src` is a git checkout of **Prettier** (the opinionated code
  formatter, `prettier/prettier`) at a pinned upstream revision from
  before this bug was fixed. It is a real upstream tree, exactly as the
  project ships it:
  `src/`, `tests/`, everything is the project's own code, unchanged. The
  bug is still present in this tree.
- All runtime and test dependencies are already installed under
  `/app/src/node_modules` (`npm install` ran at image build time). The test
  runner is `/app/src/node_modules/.bin/jest`. There is **no network** in
  this container: do not run `npm install`, `npm update`, `git fetch`, or
  any download. Everything you need is on disk. `node --version` is 22.x.

## The bug

A user reports that formatting an HTML file normalizes attribute names to
lowercase on some well-known tags but not others. On this input:

```html
<span CLASS="should print as lowercase">text</span>
<div CLASS="should print as lowercase">text</div>
```

`node bin/prettier.js <file>` today rewrites the `<div>` attribute to
`class` but leaves the `<span>` attribute uppercase:

```html
<span CLASS="should print as lowercase">text</span>
<div class="should print as lowercase">text</div>
```

The same attribute therefore gets different casing depending on which tag
carries it, and uppercase attribute names leak into formatted output on
common tags (`span`, `section`, `header`, ...). Attribute names on
well-known HTML tags should always be normalized to lowercase.

Your job: reproduce the failure, find the cause inside the Prettier source
at `/app/src`, and fix the formatter so attribute-name normalization is
consistent on all known HTML tags.

## Steps

1. Reproduce:

   ```
   node /app/reproduce.js
   ```

   Today it prints the formatted output with `<span CLASS=...>` still
   uppercase (and exits 1).

2. Localise the cause in `/app/src` and make the minimal source change that
   fixes it.

3. Verify your fix:

   ```
   node /app/reproduce.js
   ```

   must exit 0 and print the formatted output with both attributes
   lowercased:

   ```html
   <span class="should print as lowercase">text</span>
   <div class="should print as lowercase">text</div>
   ```

## Acceptance criteria (what will be checked)

1. `node /app/reproduce.js` exits 0 with `class=` on both tags.
2. The project's own HTML test suites still pass, run with the project's
   own runner from `/app/src`:

   ```
   ./node_modules/.bin/jest tests/format/html/attributes tests/format/html/case tests/format/html/basics tests/format/html/tags tests/unit/html-elements.js --config jest.config.js --runInBand
   ```

   These suites include the regression tests for this exact bug (the
   benchmark supplies them during grading). Run them yourself while you
   work and leave them green.
3. Attribute-name casing is consistent across known HTML tags: an attribute
   name Prettier recognises must be lowercased on every well-known HTML
   tag, whether or not that tag has entries in Prettier's per-element
   attribute tables, exactly as it already is on tags like `<div>`.
   Attribute names on tags that are **not** HTML tags (custom elements like
   `<my-widget>`, unknown tags) keep their case, and attribute names
   Prettier does not recognise keep their case, as they do today.
4. The tree is otherwise untouched: the only file that may differ from the
   pinned upstream revision is the single source file your fix changes. Do
   not modify or add upstream tests, do not add scratch files inside
   `/app/src` (the benchmark supplies its own regression tests during
   grading; keep anything you create in `/tmp`). The fix may be left
   committed or uncommitted in the working tree.

## Deliverable

The repaired Prettier tree at **`/app/src`**.