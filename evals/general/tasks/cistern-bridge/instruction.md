# Remove event-handler attributes that keep their original case

## Situation

`/app/src` is a clean, pinned, shallow clone of the DOMPurify project
(`https://github.com/cure53/DOMPurify`), version 3.4.13, on a detached HEAD at
the exact upstream revision this task is based on (check with
`git -C /app/src rev-parse HEAD`). The working tree is byte-for-byte the
upstream source at that revision, and it contains a real sanitizer defect. The
project's built artifacts under `dist/` are committed and present, and
`node_modules` is fully installed — including jsdom 29.1.x, qunit, jquery and
the TypeScript/rollup build toolchain. Node 22 and npm are on PATH, and the
project's own test suite is green at this revision:

```
cd /app/src && node test/jsdom-node-runner.js --dot
```

There is **no network at trial time**: `npm install` and `git fetch` will not
work, and everything you need is already in the image.

## The bug

DOMPurify sanitizes input in two forms: an **HTML string**, or an
**already-parsed DOM node** (a Node/Element taken from the document). When the
input is a node, attribute names stay exactly as the caller created them — the
DOM API does not lowercase them. That includes event-handler attributes
inserted with uppercase or mixed-case names via `setAttributeNS` /
`createAttributeNS`, or imported from an XML/XHTML document.

For such case-preserving input the sanitizer currently fails to remove:

- event-handler attributes whose names contain uppercase letters — e.g.
  `ONCLICK`, `ONERROR`;
- an uppercase `HREF` whose value is a `javascript:` URL.

So a node like `<img src="x" ONERROR="alert(1)">` survives `sanitize(node)`
with the handler still attached, and so does `<a HREF="javascript:alert(1)">`.
When such a subtree is later serialized back into an HTML document, the
browser's parser lowercases the surviving attribute names and the handlers
re-arm — a genuine security problem. The same payload given as an HTML string
is cleaned normally, and a lowercase `onerror` attribute on node input is also
removed today; only the case-preserved names slip through.

## Reproducing the failure

```
node /app/repro.js
```

builds DOM nodes with case-preserved attributes (`ONERROR`, `ONCLICK`,
uppercase `HREF=javascript:`, plus a lowercase control and a string-input
control), sanitizes them, and exits 1 while listing what survived. On this
checkout it exits 1: three case-preserved attributes survive. After your fix,
every check in it must pass (exit 0).

## What you need to do

Fix the sanitizer in the checked-out tree at `/app/src` so that event-handler
and other risky attributes are removed regardless of the case their names were
created with, while:

- lowercase event-handler attributes keep being removed (node input);
- HTML-string input keeps being cleaned exactly as it is today;
- attributes the project deliberately keeps (e.g. `alt`, `data-*`, `src`,
  `href="#..."`) are still kept — do not "fix" this by removing more than the
  defect requires.

The project develops in TypeScript source and commits the built artifacts
under `dist/`, and its own test machinery loads the built artifact — so if you
change the source you must rebuild the artifact with the project's own build
and verify against the rebuild. Drive your work with the project's own test
suite:

```
cd /app/src && node test/jsdom-node-runner.js --dot
```

must stay green, exactly as it is at this revision. You may write scratch
scripts for verification, but the verdict is made by the verifier, which also
runs the project's own regression tests for this behavior and additional
hidden cases of its own.

## Constraints

- The deliverable is the repaired `/app/src` tree: the changed source plus the
  rebuilt committed artifacts, nothing else. Do not rewrite history, do not
  add or modify git remotes, do not touch `.git` configuration, build
  configuration, lockfiles or test files. The verifier asserts that HEAD is
  unchanged, that the only modified files are the necessary source and the
  committed build artifacts, and that no new files were added anywhere in the
  clone — keep scratch work outside the clone.
- Do not modify anything under `/opt/golden`, `/tests` or `/solution`; they
  belong to the harness. `/app/repro.js` is yours to run and read.
- Do not use the network. Everything is installed; if something looks missing,
  you are looking at the wrong thing.

## What the verifier checks

1. Tree provenance: HEAD at the pinned revision, no git remotes, the upstream
   fix for this defect not present in the clone, only the necessary source and
   the committed build artifacts modified, no new files, and no stray files
   inside the clone.
2. `/app/repro.js` exits 0.
3. The project's own upstream regression tests for this defect pass against
   your rebuilt artifact.
4. The project's own full jsdom suite still passes.
5. Hidden cases over inputs the upstream tests do not use: other elements and
   handlers, several case-preserved attributes on one node with safe-attribute
   preservation, and a reparse-sink scenario proving no handler can re-arm.