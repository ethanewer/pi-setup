# rudder-main — build notes (image authoring reference)

This image was produced from the environment/Dockerfile. It clones the real
statsmodels/statsmodels repository and detached checks out the pinned parent
commit into /app/src with a depth-1 object store, editable-installs the
package warm, and runs both-directions confirmations at build time.

Authoring-time measurements (bench-base:python-3.12, 1 CPU):

- apt toolchain + git:           ~15 s
- pip dependency install:        ~25 s
- depth-1 clone + detach:        ~10 s
- `pip install -e . --no-build-isolation`: ~40 s
- the project's own regression test module
  (statsmodels/regression/tests/test_regression.py): 369 passed, 2 skipped
  in ~3 s wall
- image unique size:             ~755 MB
- build_timeout_sec = 1800 gives a >20x margin over the ~65 s measured fresh
  build.

The trial needs no network: the reproduction uses only NumPy-random data, the
whole project test module is self-contained, and pytest is baked in.