# Working checkout: pypa/pip (development tree)

- The pip source tree is cloned at `/app/src`, checked out at the exact
  revision this task was measured against (detached HEAD at the pinned
  commit). The Python package lives under `/app/src/src` (note the nested
  `src` directory).
- To use the checkout *instead of* the pip that came with the image, put
  `/app/src/src` first on `PYTHONPATH`:

      cd /app/src && PYTHONPATH=src python3 -c "import pip; print(pip.__file__)"

  (`python3 -c "import pip"` without that prints the base image's own pip;
  with it, the checkout wins, so edits you make under `/app/src` take
  effect immediately.)

- The container has no network. Do not try to `pip install` anything new or
  fetch git objects; everything you need is already installed.

- Running the project's own test suite: from `/app/src`,

      cd /app/src && PYTHONPATH=src python3 -m pytest -o addopts= -q tests/unit/...

  uses the checked-out code (the `-o addopts=` keeps the project's own
  pytest configuration, including its network-socket guard, out of the
  way for quick local runs). The focused unit tests run in seconds.

- The checkout is a git repository. A quick `git status` / `git diff` inside
  `/app/src` is the fastest way to see what has been changed. Use `/tmp` for
  scratch files, not the repository.