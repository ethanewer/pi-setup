# ballast-overtake — build environment notes

- Real repository: `networkx/networkx`, cloned at build time into `/app/src`
  at the pinned parent commit (shallow, detached, fix commit never fetched
  into this clone). Installed editable (`pip install -e /app/src`).
- Python 3.12.13; pinned deps: `numpy==2.5.3`, `scipy==1.18.1`,
  `pytest==9.1.1`.
- The environment has **no network** at trial time; everything was warmed at
  image build time (clone, editable install, and a warm run of the project's
  link-analysis tests against the pristine parent tree).
- `cpus = 1`; `OMP_NUM_THREADS`/`OPENBLAS_NUM_THREADS`/`MKL_NUM_THREADS`/
  `NUMEXPR_NUM_THREADS` are pinned to 1 for deterministic LAPACK behavior.
- `/opt/golden/test_hits.py` is the upstream regression-test file extracted
  from the fix commit at image build time (read-only reference for the
  verifier; never part of the trial clone).