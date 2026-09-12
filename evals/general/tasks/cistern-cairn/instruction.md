# Clearing a cookie can silently resurrect it

## Situation

`/app/src` is a shallow, pinned clone of the Express web framework
(`https://github.com/expressjs/express`), checked out at upstream commit
`160b91cbf79b595712b694c3513c347551d17fbe`. Its runtime dependencies and the
test tooling (mocha, supertest) are already installed in `/app/src/node_modules`.
There is **no network** at trial time: `npm install`, `git fetch` and anything
that downloads will not work, but everything you need is already present.

## The bug

Express has a `res.clearCookie(name, options)` helper that is supposed to
delete a cookie by sending it with an already-expired `Expires` date (1 Jan
1970). It accepts the same `options` object that `res.cookie` does, and the
options a caller passes are allowed to win over that forced expiration. As a
result, two common call shapes keep the cookie alive instead of deleting it:

- passing `maxAge` while clearing emits a "keep-alive" `Max-Age` value **and**
  moves the `Expires` date into the future, so the cookie is re-created for a
  short lifetime rather than removed;
- passing an explicit `expires` date emits that future date instead of the
  1970 expiry.

In both cases the session or preference the application tried to delete keeps
coming back.

## Reproducing the failure

```
node /app/probe.js
```

prints the `Set-Cookie` header produced by `clearCookie('sid', { path:
'/admin', maxAge: 1000 })` and by a `clearCookie` that passes a future
`expires` date. With the bug present the first shows `Max-Age=1` plus a future
`Expires`, and the second shows the caller's future date — neither says
`Thu, 01 Jan 1970 00:00:00 GMT`.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && NODE_PATH=$PWD/node_modules ./node_modules/.bin/mocha --require test/support/env test/res.clearCookie.js test/res.cookie.js
```

Those two cookie test files are green at the pinned commit; keep them green
while you fix the bug.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that **clearing a cookie
always emits the forced past expiration and never any `Max-Age`**, no matter
what options the caller passes. A cleared cookie must produce a `Set-Cookie`
header whose `Expires` is `Thu, 01 Jan 1970 00:00:00 GMT` and that contains no
`Max-Age` attribute, while still honouring unrelated passthrough options the
caller supplies (for example `path`, `domain`, `secure`, `sameSite`,
`httpOnly`).

## Constraints

- Network is unavailable; everything needed is already installed.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, fetch, add remotes, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree is still at the pinned
  commit, that no tracked files other than the single buggy source file were
  modified, and that the fix keeps the project's own cookie tests green
  together with the (extracted) upstream regression tests.

## What the verifier checks

1. The tree is still at commit `160b91cbf79b595712b694c3513c347551d17fbe`, no
   extra tracked files were changed, and only the minimal source surface is
   modified.
2. The project's upstream regression tests for this behaviour (clearing with a
   `maxAge` and clearing with an explicit `expires`) pass.
3. The project's own existing cookie test files still pass.
4. Hidden cases over inputs the upstream tests do not use pass, covering a
   large keep-alive `maxAge` with `domain`/`httpOnly`, a far-future `expires`
   and a negative `maxAge`, and `secure`/`sameSite` combos.

Deliverable: the repaired `/app/src` tree.
