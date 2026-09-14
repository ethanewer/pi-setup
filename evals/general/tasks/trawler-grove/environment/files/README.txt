Environment notes for trawler-grove.

- /app/src is the pinned clone of python-poetry/poetry (parent commit
  b8383e3cda4e7336eb9048b1e7388b5b914a4653), installed editable into
  /opt/poetry-venv, so `import poetry` is the checked-out tree.
- Run tests from /app/src with:
    /opt/poetry-venv/bin/python -m pytest <paths> --no-header -p no:randomly -o addopts=""
- The git-backend test file tests/vcs/git/test_backend.py is offline and
  fast. The clone has no git remotes and the object store holds only the
  pinned parent commit.
- /opt/golden, /opt/prefix, /tests and /solution are harness-owned; do not
  touch them.