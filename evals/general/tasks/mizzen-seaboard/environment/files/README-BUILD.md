# Environment notes (mizzen-seaboard)

- The psycopg source tree lives at `/app/src` (a pinned historical commit,
  detached HEAD, working tree clean). The Python package is at
  `/app/src/psycopg/psycopg/`; the pooling extra is at
  `/app/src/psycopg_pool/`.
- The package is ALSO installed as a non-editable copy in site-packages:
  `python3 -c "import psycopg; print(psycopg.__file__)"` shows
  `/usr/local/lib/python3.12/site-packages/psycopg/__init__.py`. After you
  edit the tree, use one of:
  - run your checks with the tree's package dir forced onto `sys.path`
    (this is what the `/app/repro.sh` contract described in the task
    instruction does via `PSYCOPG_PACKAGE_DIR`), or
  - refresh the installed copy from your tree yourself:
    `rm -rf /usr/local/lib/python3.12/site-packages/psycopg && cp -a
    /app/src/psycopg/psycopg /usr/local/lib/python3.12/site-packages/psycopg`.
    (Do not use `pip install` against the tree: this container has no
    network, so pip's build isolation would fail.)
- `/opt/prefix/psycopg` is a pristine read-only copy of the package exactly
  as it was at the pinned commit, baked into the image at build time. It is
  the default target of `/app/repro.sh`.
- There is NO network in this container. Everything you need is already on
  disk or installed.
- `cpus = 1`. pytest is installed; when running it from `/app/src`, point
  its cache away from the tree
  (`python3 -m pytest tests/test_*.py -o cache_dir=/tmp/pytestcache`) and do
  not leave new files inside `/app/src` (the graded checks refuse them).
- The git repo in `/app/src` is system-trusted (`safe.directory`), so you
  can read `git status` / `git diff` as a regular user.