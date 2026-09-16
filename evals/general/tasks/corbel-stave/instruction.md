# Fix falcon's route resolution and ship a compliant WSGI app

## Context

`/app/src` contains a shallow clone of **falcon 4.3.1** (`falconry/falcon`,
commit `e18c27f454b58041c9a48e921f75182aa204d8a9`), installed *editable* into
the Python environment, so any change you make under `/app/src/falcon/` is
live the moment you save it — no rebuild is needed. falcon is a pure-Python
WSGI/ASGI micro-framework with **no runtime dependencies**.

The environment already contains: Python 3.12, pytest 8.3.5, and the falcon
source tree with its full self-test suite under `/app/src/tests`. There is **no
guaranteed network** in this container: the environment may have no egress at
all, and everything you need is already on disk. Do not attempt to download
anything. falcon's own test suite runs offline (`python -m pytest -p
no:cacheprovider <modules>` from `/app/src`).

## The problem

falcon's URI router is misbehaving. When two registered route templates could
both match the same incoming path — a literal segment like `/v1/items/special`
next to a parameter segment like `/v1/items/{item_id}`, or a parameter segment
that is a prefix of a longer template — the router resolves the request to the
wrong resource, and which one wins depends on the order the templates were
registered. Correct falcon behavior is **deterministic and registration-order
independent**: for any route table, a literal segment must always beat a
parameter segment at the same position, and a more specific template must
always beat a less specific one, regardless of `add_route` order.

Your first job: find the defect inside the framework's routing implementation
and fix it so that

1. **all** of these falcon test modules pass from `/app/src`:

   ```
   python -m pytest -p no:cacheprovider tests/test_uri_templates.py \
       tests/test_uri_converters.py tests/test_compiled_router.py \
       tests/test_default_router.py tests/test_middleware.py -q
   ```

   Do not delete, skip, or alter any test. Do not weaken the framework's
   behavior; fix the framework.

## The deliverable: /app/app.py

Write a WSGI application at **`/app/app.py`** built with falcon that is driven
by a route table. It must satisfy this contract exactly.

### Input

`/app/app.py` reads a JSON route table from the path in the environment
variable `FALCON_ROUTES` (for example `/app/routes.json`). The table has the
shape:

```json
{
  "routes": [
    {"template": "/v1/things/{thing_id}", "label": "thing"},
    {"template": "/v1/things/featured", "label": "featured"}
  ],
  "middleware": ["alpha", "beta"]
}
```

- `routes`: an array (any length, registration order is *significant only*
  because routes are registered in the given order) of `template`/`label`
  entries. Templates use falcon's URI template syntax, including converters
  such as `/v1/nodes/{nid:int}`.
- `middleware`: an array of names. The app must register **one falcon
  middleware component per name, in the given order** (falcon applies
  `process_request` handlers in registration order and `process_response`
  handlers in reverse registration order).

### Behavior

- The module must define a module-level `app` (the `falcon.App` instance) and
  must **not** start any server, port listener, or thread at import time.
- Every route answers `GET`. A match returns HTTP 200 with
  `Content-Type: application/json` and body

  ```json
  {"label": "<the entry's label>", "params": {"<field>": <matched value>, ...}}
  ```

  `params` contains every template field matched by the request path; values
  are exactly what falcon's router produced (so an `{nid:int}` field is echoed
  as a JSON number, plain fields as strings).
- A request whose PATH does not match any registered template must get the
  framework's default 404 response (status 404). Do not add a catch-all sink
  or a responder for `'/'`.
- Every response produced by the app (including 404s) carries a response
  header `X-Chain` whose value is the list of middleware names from the table
  in **reverse** registration order, joined with `", "` (falcon's middleware
  contract: `process_response` runs last-registered-first). For the example
  table above, `X-Chain` must be exactly `beta, alpha`.

### Fixed things

- Do not modify `/app/routes.json` (the shipped visible table) and do not
  special-case any label, template, path, or port in the app code. The
  verifier will run your app against hidden route tables with different
  routes and middleware lists.
- Do not hardcode routing decisions; route via falcon's router.

## Constraints

- You may modify anything under `/app/src` (framework internals) and add any
  files under `/app` except `/app/routes.json`.
- `cpus = 1`; the container itself enforces it. No network; do not attempt to
  download anything.
- The verifier will (a) run the five falcon test modules above, and (b) copy
  hidden route tables over `/app/routes.json`-style tables, restart your app
  against each one, and probe it over HTTP on 127.0.0.1. Both must pass.

Signs you are done: all five test modules above go fully green, `/app/app.py`
serves `/app/routes.json` with correct labels/params/404s and
`X-Chain: beta, alpha`, and your fix produces identical route resolution no
matter what order the same templates are registered in.