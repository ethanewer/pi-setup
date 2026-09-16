# Client IP detection must see every forwarded-for hop

## Situation

`/app/src` is a shallow, pinned clone of the gin web framework
(`https://github.com/gin-gonic/gin`), checked out at upstream commit
`915e4c90d28ec4cffc6eb146e208ab5a65eac772`. The Go 1.24.0 toolchain is
installed, the module and build caches are already warm, and the project's own
test runner is `go test` (it discovers the repository's `*_test.go` files).
There is **no network** at trial time: you cannot clone again, `git fetch`
will not work, and `go` will not download anything.

## The bug

`Context.ClientIP()` is the framework's best-effort answer to "which client IP
should I log, rate-limit, or allow/deny on?" When the request reaches a proxy
that trusts a forwarded client-IP header such as `X-Forwarded-For` (configured
and trusted through the engine's trusted-proxies machinery), the method walks
the header's address list from the right, skips addresses that belong to
trusted proxies, and returns the first untrusted address it finds — the
rightmost untrusted hop. A single header line carrying
`X-Forwarded-For: 11.22.33.44, 55.66.77.88` correctly resolves to `55.66.77.88`.

Real proxy chains, however, commonly append a **new header line per hop**
instead of rejoining the value. A request through two proxies then arrives with
two separate `X-Forwarded-For` lines, for example `X-Forwarded-For:
11.22.33.44` plus a later `X-Forwarded-For: 55.66.77.88`. This checkout only
consults the **first** line, so it reports `11.22.33.44` — the leftmost address
— where it should report `55.66.77.88`, the rightmost untrusted address. Any
IP-based logging, rate limiting, or allow/deny decision then sees the wrong
address.

## Reproducing the failure

A ready-made probe lives at `/app/probe_clientip_test.go`. Run it with the
project's own test runner by copying it into the checked-out tree:

```
cp /app/probe_clientip_test.go /app/src/
cd /app/src && go test -v github.com/gin-gonic/gin -test.run TestProbeClientIPMultiLines
```

It builds a two-proxy request (two `X-Forwarded-For` lines) arriving through a
trusted platform proxy and asserts that `c.ClientIP()` returns `55.66.77.88`.
In this checkout it fails, reporting the leftmost address instead. You can
drive `ClientIP()` yourself from a small test — the framework's own test file
`context_test.go` shows the setup idiom (`CreateTestContext`,
`http.NewRequest`, `SetTrustedProxies`).

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that when several header
lines carry the forwarded-for chain, **every** line is consulted and
`ClientIP()` returns the rightmost untrusted address exactly as it does for a
single line — `11.22.33.44, 55.66.77.88` → `55.66.77.88`, and the two-line
request above → `55.66.77.88` — without changing the result of any existing
single-line case.

Drive your work with the project's own test runner from `/app/src`:

```
cd /app/src && go test -v github.com/gin-gonic/gin
```

The whole existing suite is green at the pinned commit; keep it that way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change **only** what the fix requires, in
  place. When you are done the working tree must still be at the pinned commit
  `915e4c90d28ec4cffc6eb146e208ab5a65eac772` and must differ from it in
  exactly the minimal source change — nothing else modified, added, or
  deleted. In particular, delete the probe file you copied in once you are
  done, and re-run `git status` to confirm.
- Do not rewrite history, re-clone, fetch, or change build or package files.
  Files under `/opt/golden`, `/tests` and `/solution` are harness-owned; do
  not touch them.
- Experimental files you create while debugging (scratch tests, probes) must
  be deleted before you finish.

## What the verifier checks

1. The tree is still at the pinned commit, only the minimal source surface is
   changed, no tracked files other than that were touched, and nothing was
   added inside the repository.
2. The project's own upstream regression tests for this behaviour pass.
3. The project's own existing test suite still passes.
4. Hidden cases over inputs the visible probe does not use pass — a three-line
   proxy chain, an alternative trusted header (`X-Real-IP`), and malformed
   lines in the chain.

Deliverable: the repaired `/app/src` tree.