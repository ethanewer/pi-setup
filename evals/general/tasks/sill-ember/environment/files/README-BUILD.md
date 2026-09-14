# sill-ember build notes

The image at `/app/src` is a real checkout of **Express** (expressjs/express,
https://github.com/expressjs/express), version 4.19.0, detached at the pinned
parent commit `a1fa90fcea7d8e844e1c9938ad095d62669c3abd` — the upstream bug
this task is about is present in the working tree.

- The repository's full dependency set (runtime + dev, including `mocha` and
  `supertest`) is already installed in `/app/src/node_modules`; the whole
  reproduce/fix/verify loop is offline. There is no network in the trial.
- The clone is shallow and detached; the `origin` remote has been removed.
  `git fetch`, `npm install` and any download will fail. Do not modify
  `node_modules`.
- Test runner: `node_modules/.bin/mocha --require test/support/env <files>`.
- The upstream regression test for this bug (the version of
  `test/res.location.js` from the fix commit) is baked into the image at
  `/opt/golden/res.location.js`; the verifier plants it during grading.
- `cpus = 1` — one vCPU; do not launch parallel builds or test runs.
- The trial user is uid 1000; `/app` and `/app/src` are world-writable.