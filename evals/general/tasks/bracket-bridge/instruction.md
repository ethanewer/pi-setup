# Requests on connections without a peer address must not crash

## Situation

`/app/src` is a shallow, pinned clone of the falcon project
(`https://github.com/falconry/falcon`), checked out at a specific upstream
commit, and installed from that tree in editable (development) mode, so the
code you import is exactly the checked-out Python source. Python 3.12 and
pytest are installed. There is **no network** at trial time: everything you
need is already in the image; `pip` and `git fetch` will not work.

Falcon is an ASGI+WSGI web framework. On the ASGI side, each connection is
described by a connection scope. The scope normally carries a `client`
field: a two-element iterable of `(ip, port)` describing the peer. Falcon's
request objects expose the peer's address through the `remote_addr`
attribute, and the full chain of addresses through `access_route`. When the
`client` field is absent from the scope, both fall back to the documented
default `'127.0.0.1'`.

## The bug

Some deployments legitimately have **no peer address**: a server bound to a
Unix domain socket, or a proxy that deliberately clears the client field.
The ASGI spec treats `client` as optional, and in practice a server
(e.g. uvicorn on a Unix socket) may explicitly set `scope['client']` to
`None`. In this checkout, when the connection scope carries `'client':
None`, any code that reads the request's remote address crashes:

```
TypeError: cannot unpack non-iterable NoneType object
```

The request can otherwise be served normally; the crash happens only when
the client address is inspected, which any app or middleware that logs or
uses the client's IP will do. The documented fallback to `'127.0.0.1'` is
bypassed.

## Reproducing the failure

```
python3 /app/probe_scope_client.py
```

On this checkout it raises the `TypeError` above and exits non-zero. The
same thing as a one-liner:

```
python3 -c "import asyncio; from falcon.asgi import Request; from falcon import testing
async def m():
    scope = testing.create_scope()
    scope['client'] = None
    print(Request(scope, None).remote_addr)
asyncio.run(m())"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that when the
connection scope's `client` field is `None`, the request's remote address
falls back to `'127.0.0.1'` **exactly as it already does when the field is
missing** — no exception.

The behaviour contract your fix must satisfy:

- Scope without a `client` field: `remote_addr == '127.0.0.1'` and
  `access_route == ['127.0.0.1']` (already true today; keep it that way).
- Scope with `'client': None`: `remote_addr == '127.0.0.1'` and
  `access_route == ['127.0.0.1']`, no exception (currently crashes).
- Scope with a real client address: unchanged — `remote_addr` reflects the
  client address, and proxy headers such as `X-Forwarded-For` still take
  precedence in `access_route`, with the fallback appended when `client` is
  `None`.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest tests/asgi/test_request_asgi.py -q -p no:cacheprovider
```

The project's own ASGI request tests are green at the pinned commit; keep
them that way. Add your own tests if that helps you verify (for example a
request object whose scope has `client=None` and proxy headers, or a full
ASGI app reached through `falcon.testing.simulate_get` with a null client),
but the verdict on your fix is made by the verifier, which also checks its
own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree remains at the pinned
  commit, that no tracked files outside the repair were modified, and that
  no new files were added inside the falcon package.

## What the verifier checks

1. The tree is still at the pinned commit, the upstream fix was not fetched
   by the agent, no extra tracked files were changed, and the repair touches
   only the minimal source surface.
2. The project's upstream regression test for this behaviour passes.
3. The project's own existing ASGI request tests still pass.
4. Hidden cases over inputs the upstream test does not use pass: a null
   `client` combined with `X-Forwarded-For` / `X-Real-IP` proxy headers at
   the request level, and an end-to-end request through a real ASGI app
   whose connection scope has `'client': None`, plus a guard that requests
   with a normal client address behave exactly as before.

Deliverable: the repaired `/app/src` tree.