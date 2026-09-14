# lazaret-careen — build environment notes

- Real repository: `networkx/networkx`, cloned at build time into `/app/src`
  at the pinned parent commit (shallow, detached, fix commit never fetched
  into this clone). Installed editable (`pip install -e /app/src`).
- Python 3.12.13; pinned test dependency: `pytest==9.1.1`. The networkx GML
  reader/writer is pure python (stdlib only); no numpy/scipy are needed by
  anything this task exercises.
- The environment has **no network** at trial time; everything was warmed at
  image build time (clone, editable install, and a warm run of the project's
  own GML test module against the pristine parent tree).
- `cpus = 1`; `OMP_NUM_THREADS`/`OPENBLAS_NUM_THREADS`/`MKL_NUM_THREADS`/
  `NUMEXPR_NUM_THREADS` are pinned to 1.
- `/opt/golden/test_gml.py` is the upstream regression-test file extracted
  from the fix commit at image build time (read-only reference for the
  verifier; never part of the trial clone).
- `git config --system --add safe.directory '*'` is set so the clone works
  whether the trial runs as root or as uid 1000.