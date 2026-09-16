# Notes on building and testing this tree

The repository at `/app/src` is a real upstream project (pylint) checked out
at a pinned, shallow (single) commit. Everything needed to work on it offline
is baked into this image:

- pylint installed editable (`pip install -e .`) from `/app/src`, with the
  dependency versions the mining run verified (astroid 4.2.0b4 and friends).
  Because the install is editable, edits you make to the Python sources under
  `/app/src/pylint/` take effect immediately — no rebuild step.
- pytest and the project's test suite are present: the project's own
  functional tests run with `python3 -m pytest tests/test_functional.py -k
  <name> -q` from `/app/src`.
- `cpus = 1`: one vCPU. Do not launch parallel test runs.

Common commands (all offline):

    cd /app/src
    python3 -m pylint --version
    python3 -m pytest tests/test_functional.py -k access_to_protected_members -q

There is **no network** in the trial container: do not attempt `git fetch`,
`pip install` or any download. The `.git` directory is intentionally shallow;
do not commit, fetch, pull or otherwise modify it, and leave the working tree
clean apart from your fix.