# gaff-gate

## The failure a customer reported

A customer is running an HTTP API built on the Node.js web framework checked
out at `/app/src` (a real upstream snapshot, version 5.0.0-beta.3 era, with its
dependency tree already installed in `/app/src/node_modules`). They reported
that **setting a response status code to an invalid value is silently
accepted**, and the damage only shows up later, in the client:

- `res.status(99)` — a status below 100 — is fine at first and the request
  completes, but the client receives a broken or meaningless status line.
- `res.status(1000)` — a status above 999 — behaves the same way.
- `res.status(200.1)`, `res.status('200')`, `res.status(NaN)`, and
  `res.status(undefined)` are also stored as the response status without any
  complaint, and the request then completes with a wrong, unparseable, or
  nonsensical status — for example a client that should have seen an error
  status sees `200 OK` instead.

The failure mode is silent: nothing throws, nothing logs, nothing is rejected
at the moment the invalid value is set. The customer's expectation is that an
invalid status code **fails immediately, at the point where it is set**, with a
clear error, instead of being accepted and poisoning the final response.

Your job: find the defect in the framework code under `/app/src`, demonstrate
it with your own failing reproduction, and repair the tree so that invalid
status codes are rejected immediately while every existing behaviour that
depends on status codes keeps working.

## The status-code contract you must make the tree enforce

A response status code is valid if and only if it is **an integer between 100
and 999 inclusive**. Every status-setting path must enforce this:

- anything that is **not an integer** — fractional numbers like `100.5` or
  `302.9`, numeric strings like `'200'`, `NaN`, `undefined`, `null`, booleans,
  objects, arrays — is rejected with a **`TypeError`**;
- an **integer outside 100..999** — `99`, `0`, `-1`, `1000` — is rejected with
  a **`RangeError`**;
- every rejected value must throw an error whose message **begins with the
  text `Invalid status code:`**;
- a valid integer status code (including the boundary values `100` and `999`)
  must still be accepted, set on the response, and be chainable exactly as
  today;
- the rejection must be observable at the HTTP level: when a handler sets an
  invalid status and ends the response, the client must receive a **500
  response whose body contains `Invalid status code`** rather than a silently
  corrupted 2xx — which is what Express produces for a handler that throws.

The framework's status-setting entry point is the method invoked by
`res.status(code)`. Note that other response helpers that let a caller pass a
status code (for example the helper that sends a status code plus a text body)
go through the same entry point and must also reject invalid values — our
hidden verifier checks that path too.

## The deliverable: `/app/reproduce.js`

Before you fix anything, author a **reproduction script** at `/app/reproduce.js`
(a Node.js script, runnable exactly as `node /app/reproduce.js` from any
directory). It is your regression test for this defect. It must:

- load the framework **from the tree** at `/app/src` — module resolution must
  reach the actual code you are repairing, never a copy;
- exercise a representative set of invalid status codes of the classes above
  (out-of-range integers, non-integers, a string, `NaN`, and at least one
  missing value such as `undefined`) and assert that **each one throws** when
  set;
- also assert that at least one valid status code (e.g. `200` and the boundary
  `999`) does **not** throw and is set correctly;
- **exit with status 0 if and only if every one of those assertions holds**
  (i.e. the tree rejects every invalid code and accepts the valid ones), and
  exit non-zero otherwise, printing to stdout which cases were silently
  accepted;
- stay deterministic and self-contained: no hard-coded pass/fail flags, no
  reading anything under `/tests`, no dependence on files outside `/app/src`.

You must demonstrate the sequence yourself: run `/app/reproduce.js` against the
unmodified tree and observe it **fail** (exit non-zero) — that is your record
that the bug is real — then repair the tree, and run it again to observe it
**pass** before you finish.

## Environment

- The framework source is at `/app/src` (the real upstream snapshot at a fixed
  commit). Install nothing.
- `/app/src/node_modules` is warmed: `express`'s runtime dependencies plus
  `mocha` 10.2 and `supertest` 6.3 are already there. Run the project's own
  tests with `/app/src/node_modules/.bin/mocha` from `/app/src`.
- The project's own test suite is the contract for "nothing else broke": your
  repair must keep the existing tests in `/app/src/test` green. Do not delete,
  skip, weaken, or rewrite existing tests, and do not edit anything under
  `/app/src/node_modules`.
- `/app/src` is a git repository pinned to its upstream commit. Do not move its
  `HEAD`, do not create commits, and do not fetch or import any other commit
  into it — the verifier audits this. Your repair must be a change to the
  working tree of `/app/src`.
- The network is unavailable at trial time. Everything you need is on disk;
  there is nothing to download.

## Acceptance summary

The verifier will:

1. require `/app/reproduce.js` to exist, run **your** reproduction against a
   pristine copy of the pre-repair tree, and require it to fail (exit
   non-zero) — proving your reproduction genuinely detects the defect;
2. run your reproduction against the repaired tree and require it to pass;
3. run the project's own regression tests from the repaired version of the
   upstream (the exact tests the upstream project added for this defect) and
   require them to pass;
4. run several of the project's own pre-existing test files from `/app/src/test`
   and require them to stay green;
5. run hidden tests of the status-code contract above using inputs the
   upstream tests do not use — including `res.status` and the helper that
   sends a status code with a text body — and require the rejection to be
   observable both at the API level (throws) and at the HTTP level (500 body
   contains `Invalid status code`).

Do not hard-code the hidden inputs; your fix must generalise to every input of
the classes described above. Do not touch anything under `/tests`, and leave
no stray files or processes behind.