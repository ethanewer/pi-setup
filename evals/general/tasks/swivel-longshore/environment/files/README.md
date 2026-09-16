# Build notes (swivel-longshore)

This image hosts a real upstream checkout (networkx/networkx) at `/app/src`:

- Base: bench-base:python-3.12. Python 3.12.13, pip 25.0.1.
- The repository is cloned at build time with `git init` plus a single
  depth-1 fetch of the pinned parent commit (40-hex SHA, asserted), then
  detached at that commit. The object store therefore contains exactly one
  commit; the upstream fix commit is provably absent (asserted at build).
- The tree is pip-installed editable (`pip install -e .`) and the pinned
  test dependencies (pytest 9.1.1, pytest-cov 7.1.0, pytest-xdist 3.8.0,
  numpy 2.5.3, pandas 3.0.5) are baked into the image, so the trial needs
  no network.
- The trial container has no network and `cpus = 1`.
- `/opt/golden/test_group.py` (the project's own group-centrality test file
  taken from the upstream fix commit, including the regression tests for
  this defect) and a pristine root-only copy of the pre-fix tree (the
  "pre-fix tree concept" the verifier runs the agent's reproduction
  against; its per-build random location is recorded in `/opt/prefix-path`,
  readable only by the verifier/oracle) are baked by the build; both are
  sha256-pinned in `/opt/pins`. `/opt/golden` and `/opt/pins` are
  root-only: the agent (uid 1000) cannot read or modify them.
- `/app/src` is writable by root and by uid 1000.
- The full task instructions are given by the harness alongside this image.