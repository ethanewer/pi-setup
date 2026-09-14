# chain-companion build environment

This image clones the real upstream repository `nltk/nltk` at exactly the
pinned parent commit `27b8ad6cd50a484590cb9409e5d2a891ab56e16c` (detached,
single shallow commit; the object store contains nothing else) and installs
it editable from `/app/src` with pip so `import nltk` loads the working tree.

Installed and pinned at build time (offline at trial time):

- `nltk` (editable, from `/app/src`)
- `numpy==2.5.3`, `pytest==9.1.1`, `pytest-mock==3.15.1`, `pyyaml==6.0.3`,
  `regex==2026.9.10`, `click==8.5.0`, `tqdm==4.70.1`, `joblib==1.6.0`,
  `defusedxml==0.7.1`

Also baked into the image (read-only, sha256-pinned):

- `/opt/golden/test_tree_golden.py` — the project's own regression test for
  the bug the task is about, extracted from the upstream fix commit at image
  build time; it does not exist in the trial tree.
- `/opt/pins/` — sha256 pins of the golden test and of the python3/git
  binaries the verifier executes.

The trial runs with `cpus = 1` and no network.