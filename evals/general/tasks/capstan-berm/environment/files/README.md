# Environment notes

You are inside a real upstream repository: scikit-image, checked out at a pinned
commit in `/app/src` and installed editable (compiled extensions were built at
image build time, so `import skimage` works).

- Python 3.12; numpy 2.1.3, scipy 1.14.1, and the project's build chain are
  installed.
- One vCPU; no network. Everything needed is baked in; do not `pip install`.
- `/app/src` is a shallow, detached git checkout. Do not commit or modify
  `.git`. The working tree is the deliverable.
- The project's own test runner is pytest; run targeted tests with e.g.
  `cd /app/src && python -m pytest -p no:cacheprovider skimage/morphology/tests`.