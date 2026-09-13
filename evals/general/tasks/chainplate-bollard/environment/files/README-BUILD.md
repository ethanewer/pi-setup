# chainplate-bollard — build environment notes

- Real repository: `networkx/networkx`, cloned at build time into `/app/src`
  at the pinned parent commit `5d160909eeb42e9844496dd2bbd19b826d2242d7`
  (shallow, detached; the fix commit is never fetched into this clone).
  Installed editable (`pip install -e /app/src`).
- Python 3.12; pinned deps: `pytest==9.1.1`. `numpy`/`scipy` are not
  installed; the mst test-file's numpy/scipy-dependent tests skip themselves
  via `pytest.importorskip`.
- The environment has **no network** at trial time; everything was warmed at
  image build time: the clone, the editable install, the fail-closed
  direct-`next()` reproduction (AttributeError at the parent), the golden
  regression nodeid failing at the parent, and a warm run of the project's
  own `networkx/algorithms/tree/tests/test_mst.py` against the pristine
  parent tree (61 passed, 22 skipped).
- `cpus = 1`; `OMP_NUM_THREADS`/`OPENBLAS_NUM_THREADS`/`MKL_NUM_THREADS`/
  `NUMEXPR_NUM_THREADS` are pinned to 1.
- `/opt/golden/test_mst.py` is the upstream regression-test file extracted
  from the fix commit at image build time (read-only reference for the
  verifier; never part of the trial clone). Its SHA-256 is
  `985c62908be34305e954fd3f747c65cdac344d2da791841cc1f949725440f132`.