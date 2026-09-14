# The test client reports the wrong raw request URI

## Situation

`/app/src` is a shallow, pinned git checkout of the falcon web framework
(`https://github.com/falconry/falcon`, version 4.0.0) at upstream commit
`7191be4d19592401f38a7b8e824e9669d34dad2b`, checked out in detached HEAD.
The framework is already installed in editable mode from that checkout, and
`pytest` is installed, so everything runs entirely offline; nothing needs to
be downloaded. The project's tests live under `/app/src/tests`.

You have one deliverable to create, `/app/reproduce_bug.py`, and one tree to
repair, `/app/src`. `/opt/golden`, `/tests` and `/solution` are harness-owned;
do not read or modify them.

## The bug, as a user would report it

*Any request we simulate with the framework's testing library sees a bogus
raw request URI. We serve URLs whose path segments contain percent-encoded
characters — for example an encoded slash, `/a%2Fb`, or an encoded UTF-8
name — and we sign and cache on the raw URI the server reports. Under our
real WSGI server (we use gunicorn, but wsgiref and uWSGI behave identically)
the environment our application receives contains the raw, still
percent-encoded request path in the WSGI environ variable `RAW_URI`, while
`PATH_INFO` carries the decoded path. Under the framework's own test client,
the very same request produces an environ in which `RAW_URI` is a single
slash `'/'` no matter which path was requested. Paths without any
percent-encoding happen to work, so the defect hides until a request with an
encoded character shows up and the application signs or caches a different
string than the server would have given it. Tests that pass against a real
server fail under the test client.*

Concretely, for a request whose path is `/cache/http%3A%2F%2Ffalconframework.org/status`:

- a real WSGI server (wsgiref, gunicorn, uWSGI) yields
  `environ['RAW_URI'] == '/cache/http%3A%2F%2Ffalconframework.org/status'` and
  `environ['PATH_INFO'] == '/cache/http://falconframework.org/status'`;
- the framework's testing library currently yields
  `environ['RAW_URI'] == '/'` while `PATH_INFO` is correct — the raw path is
  lost. That mismatch is the bug you are here to fix.

The affected behaviour is the `RAW_URI` value produced by the framework's
request-environment builder (`falcon.testing.create_environ`) and by every
testing entry point built on it, and thus what an application sees for the
raw request URI when requests are simulated with `falcon.testing.TestClient`.

## What you must do

1. **Write your own failing reproduction first**, before touching the source,
   as `/app/reproduce_bug.py`. It must be a self-contained Python script
   (standard library plus the installed falcon only; no pytest) that builds a
   request environment for a path containing percent-encoded characters (an
   encoded slash inside a path segment is a good choice), prints the observed
   `RAW_URI` and `PATH_INFO`, and exits with status **0 exactly when the
   behaviour is correct** (RAW_URI carries the raw request path and PATH_INFO
   carries the decoded path) and with a **non-zero status when the defect is
   present**. It must run as `python3 /app/reproduce_bug.py`.

   The verifier runs your script twice: once against a pristine copy of the
   original (pre-fix) tree, where it must detect the defect and exit non-zero;
   and once against your repaired `python3 /app/reproduce_bug.py` invocation,
   where it must exit 0. A script that cannot fail on the original tree has
   not captured the bug; a script that cannot pass on the repaired tree still
   reports the defect after the fix. Keep the script at `/app/reproduce_bug.py`
   when you are done — it is a deliverable.

2. **Fix the defect** somewhere in the checkout at `/app/src` so that the
   request environment reports the raw, still percent-encoded request path as
   `RAW_URI` while `PATH_INFO` keeps the decoded path, for any request path —
   including paths with no percent-encoding at all (the plain `/` request and
   plain paths must keep working, and the decoded path must keep its exact
   current form, including how non-ASCII characters are carried). The
   behaviour of everything else the testing library produces must not change.

3. **Keep the project's own tests green.** The project's own regression test
   for this behaviour lives outside the checkout (the verifier runs it from
   the harness), and the whole `/app/src/tests/test_testing.py` module (42
   tests) must keep passing on the repaired tree. Drive your work with
   `cd /app/src && python3 -m pytest tests/test_testing.py`.

## Constraints

- Work only in the working tree of `/app/src`. Do not change anything under
  `/app/src/tests/`, do not add or delete files inside the repository, do not
  commit, do not create branches or tags, do not add remotes, and do not fetch
  anything. Not more than one tracked file in the repository may differ from
  the pinned commit when you are done.
- Do not modify `/app/reproduce_bug.py` to mask the defect; its sole job is
  to detect the behaviour honestly.
- Everything needed is installed; plan for no network.

## What the verifier checks

1. The checkout is still at the pinned commit; the upstream fix is not
   reachable from the repository; the working tree differs from the pinned
   commit in exactly the one source file your repair requires; the harness's
   copy of the project's regression test is intact.
2. Your reproduction fails (non-zero exit) on a pristine copy of the original
   tree and passes (exit 0) on your repaired tree.
3. The project's own regression test for this behaviour passes on your
   repaired tree and fails on the pristine tree.
4. The entire `tests/test_testing.py` module passes on your repaired tree.
5. Hidden cases — additional request paths and testing entry points the
   regression test does not use — behave correctly on your repaired tree.

Deliverables: the repaired `/app/src` tree and `/app/reproduce_bug.py`.