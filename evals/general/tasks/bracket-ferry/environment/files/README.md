# Working checkout: pypa/pip (development tree)

- The pip source tree is cloned at `/app/src`, checked out at the exact
  revision this task was measured against (the repository's default branch,
  `main`). The Python package lives under `/app/src/src` (note the nested
  `src` directory).
- To use the checkout *instead of* the pip that came with the image, put
  `/app/src/src` first on `PYTHONPATH`:

      cd /app/src && PYTHONPATH=src python3 -m pip --version

  (`python3 -m pip --version` without that prints the base image's own pip;
  with it, the checkout wins, so edits you make under `/app/src` take effect.)

- The container has no network. Do not try to `pip install` anything new or
  fetch git objects; everything you need is already installed.

- Running the project's own test suite: from `/app/src`,

      cd /app/src && PYTHONPATH=src python3 -m pytest tests/unit/... -q

  uses the project's own pytest configuration (including its network-socket
  guard). The focused unit tests run in seconds.

- The checkout is a git repository. A quick `git status` / `git diff` inside
  `/app/src` is the fastest way to see what has been changed. Use `/tmp` for
  scratch files, not the repository.