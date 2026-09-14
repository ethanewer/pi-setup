# Case-insensitive fixed-path lookup can crash the whole server

## Situation

`/app/src` is a shallow, pinned clone of the gin web framework
(`https://github.com/gin-gonic/gin`) checked out at upstream commit
`fb2583442c4d9bccb75e6d26f1aa6e7c01950db6`, in detached HEAD with real git
history. The Go toolchain (`go` 1.26.8) is installed, all dependencies are
already downloaded and verity-checked, and the package plus its test files
are already compiled, so the whole workflow is offline and fast.

Run the project's own test runner from `/app/src`:

```
cd /app/src && go test -v github.com/gin-gonic/gin
```

The suite is green in this checkout (about 400 tests).

## The bug

The engine has a configuration option `RedirectFixedPath`, off by default.
When it is on, a request that matches no route is not answered with 404
immediately. The framework cleans the URL path (removes superfluous
elements like `..` or duplicate slashes) and does a case-insensitive lookup
of the cleaned path against the registered routes. If a fixed-path route
matches case-insensitively, the framework answers with a redirect (HTTP 301
for GET requests, 307 for other methods) to the case-corrected path. Only
if nothing matches at all does the request fall through to the normal
not-found handling.

In this checkout that case-insensitive lookup can panic and kill the whole
server process. The runtime error is `panic: invalid node type`. It affects
applications whose routing layout mixes ordinary static segments and
parameter placeholders (`:name`) under a shared prefix. When the internal
routing tree contains a node that has both static children and a wildcard
(parameter) child, a request path that does not match any static child at
that node aborts the process instead of continuing the lookup. No 404, no
redirect, no error handler runs: the process dies. Applications that
register only static routes, or only parameterised routes, never hit it. A
single mistyped or differently-cased URL on a mixed layout takes the whole
application down.

## What you need to do

1. Write your own failing reproduction first, as a go test file, at exactly
   `/app/repro_caseinsensitive_test.go`. It must drive the affected
   behaviour through gin's own APIs. The tree's existing routing tests
   (`tree_test.go`) show the direct fixed-path lookup API (a tree node,
   `addRoute`, and the case-insensitive lookup it exposes), and
   `routes_test.go` shows `New()`, setting engine options such as
   `RedirectFixedPath`, and `PerformRequest` to drive a full request
   through the router. Use either level. Every test function in the file
   must have a name starting with `TestRepro`. The reproduction must FAIL
   in this checkout, with the panic or with an assertion you can observe.
   Run it by copying it into the tree:

   ```
   cp /app/repro_caseinsensitive_test.go /app/src/
   cd /app/src && go test -v github.com/gin-gonic/gin -test.run TestRepro
   ```

   The copy inside `/app/src` is scratch: delete it before you finish.
   The file at `/app/repro_caseinsensitive_test.go` itself is a
   deliverable and stays.

2. Fix the framework's case-insensitive fixed-path lookup so it can never
   panic on any request against any routing layout. The process stays up,
   static routes still match and are corrected for case, parameter
   placeholders still match, and a genuinely unknown path still yields the
   normal not-found result.

3. After the fix, your reproduction must pass, the project's own suite
   must stay green, and the tree must differ from the pinned commit in
   exactly the minimal change that fixes the bug.

## Constraints

- The clone at `/app/src` is the deliverable. Do not rewrite history,
  re-clone, fetch, add remotes, or change package or build files. When you
  are done, the working tree must still be at the pinned commit and
  `git status --porcelain` must list only the one modified source file of
  the fix and nothing else: no new files, no staged entries.
- Experimental files you create while debugging (scratch copies of the
  reproduction, probe scripts) must be deleted before you finish.
- Files under `/opt/golden`, `/tests` and `/solution` are harness-owned;
  do not read or modify them.
- The verifier runs `go test` at one CPU, so keep the reproduction cheap
  to compile and run.

## What the verifier checks

1. The tree is still at the pinned commit, the upstream fix commit is not
   present in the clone, and the only change from the pinned commit is the
   minimal source fix.
2. Your `/app/repro_caseinsensitive_test.go` exists, genuinely fails
   against the pre-fix lookup logic (the verifier re-runs it on a copy of
   the tree with the buggy source restored), and passes against the
   repaired tree.
3. The project's own regression tests for this behaviour, extracted from
   the upstream fix at image build time into `/opt/golden`, pass against
   the repaired tree.
4. The project's own existing test suite still passes (packages gin,
   gin/binding and gin/render).
5. Hidden cases over route layouts and lookup inputs the upstream tests do
   not use pass: a deeper mixed static/param subtree, a router-level
   request through `RedirectFixedPath`, and a static leaf sharing a node
   with a catch-all route.

Deliverables: the repaired `/app/src` tree and
`/app/repro_caseinsensitive_test.go`.