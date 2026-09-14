# Fix broken link generation for extreme float route parameters

## Environment

`/app/src` contains a checked-out copy of the **Werkzeug** web library
(https://github.com/pallets/werkzeug), installed *editable* into the Python 3.12
environment, so any edit you make under `/app/src` takes effect immediately — no
reinstall step is needed. The project's full test suite lives at
`/app/src/tests` and runs offline in a few seconds:

```
cd /app/src && python -m pytest -q
```

There is **no guaranteed network** in this container and everything you need is
already on disk. Do not attempt to download anything. pytest 9.1.1 is installed.

## The problem: a user report

> Our service exposes routes like `/api/measurements/<float:value>`, and we
> generate links to those endpoints from numeric data. For most numbers the
> links work fine, but for very small values (say `0.00001`) and very large
> values (say `100000000000000000000.0`) the generated link comes out in
> **scientific notation**, e.g. `/api/measurements/1e-05`. Visiting such a link
> returns **404 Not Found**. Even inside the same application, generating the
> URL and then dispatching a request to that URL fails. Mid-range values like
> `0.815` are unaffected.

This is a genuine defect in the library installed at `/app/src`: when a URL is
generated for a route parameter with a float converter, extreme values are
rendered in a form the router itself cannot match back. Your job is to locate
and fix the defect so that every finite float value — however small, however
large, integer-valued or fractional, negative or positive — produces a URL that
(a) contains no scientific notation and (b) can be matched back by the router
to the same numeric value.

## Step 1 — write the failing reproduction (required deliverable)

Create **`/app/reproduce.py`**, a standalone Python 3 script that demonstrates
the defect through the library's public API, and keep it at that path. It must
follow this contract exactly:

- Build a routing `Map` with a single rule `/<float:v>` under endpoint `"a"`,
  and bind an adapter for host `"test.example"`.
- Take the float value to test from `sys.argv[1]` when given, otherwise default
  to `0.00001`.
- Build the URL for that value and print exactly one line: `BUILT <url>`
- Match the URL back through the adapter and print exactly one line:
  `ROUNDTRIP <endpoint> <value>`
- Exit with status 0 **only if** the built URL contains no letter `e` or `E`,
  the round-trip matched successfully, and the matched value equals the input
  value. Otherwise print a single `FAIL: <reason>` line to stderr and exit
  non-zero.

Run it against the current code: it must FAIL (that is the point of a
reproduction). The verifier will run this same script twice more later — once
against a pristine copy of the pre-fix code and once against your repaired tree
— and its output format is machine-checked, so keep the `BUILT`/`ROUNDTRIP`
lines exactly as specified.

## Step 2 — fix the library

Find the defect and repair the library so that:

1. your reproduction passes for every value listed above (`0.00001`, `1e20`,
   `2.5e-07`, `5.0`, `0.5`, `1000.0`), and
2. the library itself handles negative values too when the converter's
   `signed=True` option is used (match `-2.5e-07`, `-1e20`, `-5.0` back through
   a signed rule), and
3. the library's own full test suite stays green:

```
cd /app/src && python -m pytest -q
```

Do not delete, skip, rename, or weaken any test. The fix must live in the
library: float route parameters may be signed or unsigned (the converter's
`signed=True` option), and URL generation must never emit scientific notation
and must always produce a URL the router matches back to the same value.

## Constraints

- You may modify anything under `/app/src`. Do not change the revision the
  checkout is on, do not add or remove anything under `/app/src/tests`, and do
  not touch anything outside `/app`.
- `cpus = 1`; the container enforces it.
- No network. Do not attempt to download anything; all of the project's test
  dependencies are already installed.

Signs you are done: `/app/reproduce.py` exists with the contract above and
exits 0 for the values in Step 2's first requirement, signed values
round-trip through a signed rule, and `python -m pytest -q` from
`/app/src` passes completely.