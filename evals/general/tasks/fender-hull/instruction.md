# In-place sanitisation of a live form subtree aborts and leaves event handlers attached

## Situation

`/app/src` is a shallow, pinned clone of the **DOMPurify** HTML sanitizer
repository (`https://github.com/cure53/DOMPurify`) at upstream commit
`2c8ca25ef3cec05e12a50bd456f57a816eaa5998`, checked out in detached HEAD. Its
dependencies are already installed (`npm ci` from the project's committed
lockfile; `jsdom 29.1.1` is available from anywhere via your `NODE_PATH`).
There is no network guarantee at trial time — the task must work entirely
offline. node 22, npm and git are on `PATH`.

```
cd /app/src && node test/jsdom-node-runner   # the project's own jsdom test suite
cd /app/src && npm run build                 # regenerate dist/ from the project source (~4 s)
```

The project's own test suite is fully green at this checkout (1203 QUnit cases
pass), and the prebuilt distributables in `dist/` are built from the same
source, so the shipped tests do not show the bug below.

## The bug

Sanitizing a live DOM subtree **in place** can abort part-way through. When it
does, code that calls the sanitizer and tolerates (catches) exceptions is left
with the exact thing the sanitizer exists to remove still attached: `on*`
event-handler attributes (e.g. `onerror`, `onload`, `onmouseover`) on
descendants of the sanitized live tree.

The trigger sits on the **root element** of the in-place subtree. When that
element's reference to its owning document is intercepted — a `<form>` root is
the natural case: the sanitizer reads a document-related property directly off
the root, and a form can carry an own property (e.g. installed by application
code, or a child element whose name shadows it) that makes that direct read
return a foreign element — the sanitize call throws before it starts walking,
with an error like:

```
TypeError: 'createNodeIterator' called on an object that is not a valid instance of Document
```

The same in-place call on an un-shadowed element completes normally and strips
such handlers. Nothing in the shipped tests covers the shadowed case.

## What you must deliver

1. **`/app/repro.js`** — your own failing reproduction, written and run
   *before* you change any library source:
   - a Node script using the environment's `jsdom` package;
   - loads the sanitizer library from the path in the `DOMPURIFY_MODULE`
     environment variable, defaulting to `/app/src/dist/purify.cjs`;
   - exercises the in-place sanitisation described above and exits `0` when
     the dangerous state is absent (handler stripped) and non-zero when it is
     present (handler survives).
   The verifier runs your script twice: once against the pristine pre-fix tree,
   where it must fail (the bug is present), and once against a distributable the
   verifier itself rebuilds from your fixed source, where it must pass. The
   verdict must come from actually calling `sanitize(..., { IN_PLACE: true })`
   on the shadowed-root scenario — not from reading any files.

2. **The fixed tree at `/app/src`** — fix the project source so the symptom
   disappears: the in-place scrub of such a subtree must complete (or fail
   closed by neutralizing the live root), and no armed handler may be left
   attached in the caller's tree. Then regenerate the distributables
   (`cd /app/src && npm run build`), confirm your `/app/repro.js` now exits 0,
   and confirm the project's own suite still passes.

## Constraints

- Work only inside the container. Do not modify the repository's git history
  (no commits, no resets, no new branches or tags): the verifier checks that
  HEAD stays at the pinned commit and that your changes are uncommitted in the
  working tree.
- Do not modify any file under `test/`; the verifier checks
  `test/test-suite.js` is byte-identical to the pinned commit, then runs the
  project's own suite against the tree, overlaid with the project's own
  regression tests for this behaviour (fetched into the image at build time
  from upstream — you do not have to, and are not expected to, find them).
- Changes must be in the project source, not only in the prebuilt artefacts:
  the verifier rebuilds `dist/` from your source and discards any hand-dated
  binary, then requires your reproduction to pass, the full project suite to
  pass, and several additional hidden scenarios exercising the same in-place
  path with inputs you did not use.

Your working directory is `/app`. The reproduction deliverable goes at
`/app/repro.js`; the fixed repository stays at `/app/src`.