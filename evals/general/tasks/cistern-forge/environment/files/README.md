# cistern-forge environment notes

- Upstream checkout: `/app/src` — a git repository detached at the exact
  historical revision this task targets. The genuine bug is present; the
  upstream fix is not reachable from this clone.
- The `psycopg` package resolves straight into the source tree
  (`PYTHONPATH=/app/src/psycopg` is preset for every shell), so plain
  `python3` imports work from any working directory and your edits take
  effect immediately, without any reinstall. You can verify:

  ```bash
  python3 -c "import psycopg; print(psycopg.__file__)"   # -> /app/src/psycopg/psycopg/__init__.py
  ```

- `libpq` (runtime C library) is installed; `pytest` 9.1.1 is installed.
  The project's own tests are self-contained for the waiting module: no
  PostgreSQL server is needed, everything runs on localhost sockets.
- There is no network at trial time. Everything you need is already in the
  image; do not try to download anything, and do not re-clone `/app/src`.
- The repository is graded for provenance: leave `HEAD` where it is, make
  only the minimal library change your fix requires, and write any scratch
  files under `/tmp`, never inside `/app/src`.