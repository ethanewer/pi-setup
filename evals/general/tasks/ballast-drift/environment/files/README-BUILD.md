# Notes on building and testing this tree

`/app/src` is a real upstream project (eslint, https://github.com/eslint/eslint)
checked out at a pinned, shallow (single) commit with the origin remote removed.
Everything needed to work on it offline is baked into this image:

- Node.js 22 and npm.
- The full dependency set installed in `/app/src/node_modules` (runtime + dev
  dependencies, including mocha and espree).
- `/app/repro.js` — a reproduction script for the bug (run it from `/app/src`).

Common commands (all offline, no network required):

    cd /app/src
    node /app/repro.js            # reproduces the bug: exits 1 on this tree
    node_modules/.bin/mocha tests/lib/rules/new-cap.js   # this rule's tests

`npx --no-install mocha ...` works too. There is no lock file and the tree's
`.npmrc` sets `package-lock = false`, so do not run `npm install` (it would
re-resolve everything and is unnecessary — `node_modules` is already warm).

Do not modify the `.git` directory (its history is intentionally shallow, and
the origin remote was removed — `git fetch` cannot work). Do not commit.

The project's full test command is `npm test`; at 1 vCPU it is slow, and the
grader only runs a targeted subset (this rule's test file plus a small
selection of related rule/rule-tester tests), so prefer those.