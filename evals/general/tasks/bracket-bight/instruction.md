# Fix a streaming-response bug in Express

## Environment

- `/app/src` is a git checkout of **Express** (the Node.js web framework,
  `expressjs/express`) at its pinned pre-fix parent commit. It is a real
  upstream tree, exactly as the project ships it: `lib/`,
  `test/`, everything is the project's own code, unchanged.
- All runtime and test dependencies are already installed under
  `/app/src/node_modules` (`npm install` ran at image build time). The test
  runner is `/app/src/node_modules/.bin/mocha`; `supertest` is importable.
- There is **no network** in this container: do not run `npm install`,
  `npm update`, `git fetch`, or any download. Everything you need is on disk.
  `node --version` is 22.x.

## The bug

A user reports that their streaming endpoint is broken for every client. The
handler sets an explicit `Transfer-Encoding: chunked` header on the response
(the standard way to stream output) and then sends the body with
`res.send()`. Every client — browsers and Node's own HTTP stack — rejects the
response before the body arrives, with a parse error:

```
Parse Error: Content-Length can't be present with Transfer-Encoding
```

HTTP/1.1 forbids a sender from putting `Content-Length` and
`Transfer-Encoding` on the same response (RFC 9112 §6.3.3: "A server MUST NOT
send a Content-Length header field in any response with a Transfer-Encoding
header field"). The body never reaches the client.

Your job: reproduce the failure, find the cause inside the Express source at
`/app/src`, and fix it so the framework stops emitting the two headers
together.

## Steps

1. Run the reproducer:

   ```
   node /app/reproduce.js
   ```

   It starts a tiny Express app whose only route sets
   `Transfer-Encoding: chunked` and sends `'hello'`, then fetches it with
   Node's own HTTP client. Today it exits 1 with the parse error above.

2. Localise the cause in `/app/src` and make the minimal source change that
   fixes it.

3. Verify your fix:

   ```
   node /app/reproduce.js
   ```

   must exit 0 and print:

   ```
   Content-Length present: false | Transfer-Encoding present: true
   body: "hello"
   ```

   with the received body exactly `"hello"` — i.e. the client parsed the
   response and the payload arrived intact.

## Acceptance criteria (what will be checked)

1. `node /app/reproduce.js` exits 0 and reports no `Content-Length` while the
   `Transfer-Encoding` header is preserved and the body is delivered intact.
2. The project's own unit suite still passes, run with the project's own
   runner from `/app/src`:

   ```
   ./node_modules/.bin/mocha --require test/support/env --reporter spec test/
   ```

   Its `test/res.send.js` file carries the regression tests for this exact
   bug. You are expected to run this suite yourself while you work and to
   leave it green.
3. Responses that carry a `Transfer-Encoding` header plus a `res.send()`
   body must never also carry `Content-Length` — for any body kind: string,
   JSON object, Buffer, short or long. Responses without a
   `Transfer-Encoding` header must keep sending `Content-Length` exactly as
   they do today.
4. The tree is otherwise untouched: the only file that may differ from the
   pinned parent commit is the one source file your fix changes. Do not modify or add
   upstream tests, do not add scratch files (the benchmark supplies its own
   regression tests during grading). The fix may be left committed or
   uncommitted in the working tree.

## Deliverable

The repaired Express tree at **`/app/src`**.