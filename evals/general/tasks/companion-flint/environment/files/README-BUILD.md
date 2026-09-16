# companion-flint — build notes

This image contains the real **mypy** source tree at `/app/src`, checked out
detached at a pinned historical commit (a single depth-1 object store; the
working tree is clean). mypy runs from source:

    cd /app/src && python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /path/to/somefile.py

The project's data-driven test suite runs with pytest (xdist available; use
`-n 1` on this one-CPU container):

    cd /app/src && python3 -m pytest mypy/test/testcheck.py -k "check-typevar" -n 1 -q

`/opt/mypy-parent` holds a pristine copy of the same tree at the same pinned
commit (read-only) — useful to compare behaviour against. There is no network
in the trial container; everything is baked in.

See /app/instruction.md for the task.