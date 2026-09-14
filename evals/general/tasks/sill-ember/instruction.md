# sill-ember

You are working inside a real open-source codebase: **Express**
(`https://github.com/expressjs/express`), the web framework for Node.js,
checked out at a pinned commit in `/app/src` (the working tree starts
clean). There is a bug in one of its response helpers. Your job is to find
it, fix it in the working tree, and prove the fix — with a reproduction
script that **you** write, and with the project's own test tooling. You are
intentionally **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- Node.js 22 with npm is installed. The repository's full dependency set
  (runtime + dev, including `mocha` and `supertest`) is already installed in
  `/app/src/node_modules`, so the whole reproduce/fix/verify loop runs
  offline. Express version in this tree: 4.19.0.
- **Do not rely on the network.** Everything you need is baked into the
  image; the trial may have no network access, and the clone's `origin`
  remote has been removed — `git fetch`, `npm install` and downloads will
  not work. Do not modify `node_modules`.
- `cpus = 1`: one vCPU. Do not launch parallel builds or test runs.
- The tree at `/app/src` is shallow (a single commit) and detached at a
  pinned commit. Do not commit, fetch, or otherwise modify `.git`. The trial
  runs as uid 1000; `/app` and `/app/src` are writable.

## The bug (user-visible symptom)

The response helpers that tell the client where to go next accept a
location: a path like `/login`, a full URL like `http://example.com`, or
the special value `back`. In this tree those helpers silently break when
the location is built programmatically as a WHATWG `URL` object — the
global `URL` constructor:

```js
app.get('/go', function (req, res) {
  res.location(new URL('http://example.com/'));
  res.end();
});
```

A request to such a route is answered with **HTTP 500** and **no `Location`
header at all**: the handler crashes before producing a response. The same
failure happens when the redirect helper is handed a `URL` object. Any
application that computes its redirect targets as `URL` objects is broken —
users get a server error instead of a redirect. A non-string location value
should be treated the same as any other location: converted to its string
form up front and then handled exactly like a plain string, so the response
is a normal redirect with the expected `Location` header.

## Requirements

1. **Write your own reproduction first** and keep it as a deliverable:
   create `/app/repro.js`, a Node.js script that demonstrates the
   user-visible symptom through the project's own machinery. Contract:
   - usage: `node /app/repro.js [REPO]` — `REPO` is the path of an express
     checkout to exercise; when omitted it must default to `/app/src`.
   - It loads the express module from that checkout and exercises the
     affected helpers exactly as a client would: build a small app whose
     handler passes a `URL` object (built with the global `URL`
     constructor) to the affected location/redirect helper, dispatch an
     in-process request through `supertest` (no listening socket, no
     network, no files), and judge success from the **response**: an HTTP
     500 response, or a response missing the `Location` header, means
     failure.
   - Exit code: `0` when the checkout behaves correctly; any non-zero code
     when the bug is present or the response is not a proper redirect.
   - Deterministic and quick (a few seconds at most).
   On this tree `/app/repro.js` must **fail** (non-zero exit). The grader
   will run it against a pristine pre-fix copy of the tree (it must fail
   there) and against your final tree (it must pass).
2. **Fix the cause, not the symptom**: make the helpers convert any
   non-string location value to its string form before the rest of the
   handling, so `URL` instances and other coercible values work like plain
   strings. Do not special-case the exact inputs above, do not disable the
   helpers, and do not catch-and-swallow the crash.
3. The graded tree must be byte-identical to the pinned commit except for
   the **single source file where the bug lives**. Do not add, move, delete
   or rename any file; if you create scratch files to investigate, delete
   them before you finish; make no commits; do not modify `tests/`,
   `package.json` or any other file. The grader compares every file's bytes
   against the pinned commit's own blobs, so cosmetic side-changes also
   fail.
4. Create `/app/summary.md`: a non-empty write-up of what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce**: write `/app/repro.js`, run it with `node /app/repro.js`,
   and confirm it fails on this tree (exit non-zero).
2. **Localise**: run the project's own tests for the affected behaviour —
   `node_modules/.bin/mocha --require test/support/env test/res.location.js`
   — they pass on this tree, so now read the source under `lib/` and find
   where the location helper begins handling its argument. The first thing
   done with the argument is a string-only operation performed directly on
   it; that is the line that throws for a `URL` object.
3. **Fix** with the smallest possible change in that one source file: the
   value must be a string before any string operation runs on it. `'back'`
   alias handling, URL encoding/parsing, relative paths and the plain-string
   cases must all behave exactly as before.
4. **Prove nothing else broke**: `/app/repro.js` must now exit 0; the
   project's own `test/res.location.js` and a few neighbouring response
   tests of your choice must still pass (they pass on the pristine tree and
   must still pass after your fix).
5. Write `/app/summary.md` and delete any scratch files.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the fix commit
  is not present in the object store, that every tracked file except the
  single source file the bug lives in is byte-identical to that commit (any
  other modification, added file or untracked scratch file fails), and that
  `node_modules` is untouched;
- require `/app/summary.md` to exist and be non-empty;
- require `/app/repro.js` to fail against a pristine pre-fix copy of the
  tree and to pass against your tree;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — the upstream version of `test/res.location.js`,
  which this tree predates) over `test/res.location.js` and run it with
  mocha: all 10 cases must pass;
- run a targeted selection of the project's existing response tests
  (`res.location`, `res.redirect`, `res.set`, `res.type`, `res.send`,
  `res.json`), which must stay green;
- run authored hidden cases that reach the same code path from inputs the
  upstream test does not use (the redirect helper with a `URL` object, a
  `URL` object carrying a query string and fragment, and another non-string
  coercible value), through the project's own `supertest`.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.