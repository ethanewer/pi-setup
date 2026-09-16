# lighter-gate — environment notes

This image ships a real upstream checkout of the `click` command-line library
at `/app/src`, installed editable (so `import click` loads code from
`/app/src/src/click`). `pytest` 9.1.1 is installed. There is no network at
trial time; do not re-clone or reinstall anything.

The project's own self-contained test suite lives at `/app/src/tests` and is a
good source of ground truth while you work.

- Python: 3.12.13 (system)
- click: editable install from /app/src
- pytest: 9.1.1
- The tree at /app/src is a real upstream git checkout (detached HEAD).