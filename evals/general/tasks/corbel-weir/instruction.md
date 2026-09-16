# Release engineer: ship the click 8.5.0 release from the upstream checkout

You are the release engineer for the `click` command-line library. A real
upstream checkout of the project lives at `/app/src`. It is the exact source of
the upstream 8.5.0 tag — except that the checked-out tree has been deliberately
damaged in exactly one place, in its release metadata, so that any release built
from the tree as-is is mislabeled and would never pass upstream release review.

Produce the release and prove it, end to end, entirely offline.

## Deliverables (all must exist when you are done)

1. `/app/dist/click-8.5.0.tar.gz` — the source distribution, built from
   `/app/src` with the project's own declared build backend.
2. `/app/dist/click-8.5.0-py3-none-any.whl` — the wheel, built the same way.
3. `/app/dist/release-proof.json` — your release record, exactly this schema:

```json
{
  "version": "8.5.0",
  "installed_version": "8.5.0",
  "import_ok": true,
  "venv_python": "/path/to/venv/bin/python",
  "wheel": "/app/dist/click-8.5.0-py3-none-any.whl",
  "sdist_rebuild_version": "8.5.0"
}
```

## The release contract

The artifacts must describe the release exactly as the upstream 8.5.0 release
on PyPI does. Concretely, the installed package must report, through
`importlib.metadata`:

- name `click`, version `8.5.0`, `Requires-Python: >=3.10`,
- license expression `BSD-3-Clause` with the license file shipped in the wheel.

Do not guess at what is damaged. Build the artifacts from the checkout as-is,
inspect the metadata the built artifacts actually carry (and what a CLI built on
them reports from `--version`), compare it against the contract above, find what
does not match, and repair the checkout so a rebuild produces correct metadata.
The mislabeled artifacts must be replaced by correct ones at the deliverable
paths — nothing leaves `/app/src` unchanged except the minimal metadata repair.

The release must also be provable:

- The wheel installs into a clean virtual environment you create, with no
  network (`pip ... --no-index --no-deps`), and `import click` works from that
  environment, not from the source tree.
- The installed package's public entry points work from the installed wheel:
  `click.command`, `click.group`, `click.option`, `click.echo`,
  `click.version_option`, `click.confirm`, `click.IntRange`, `click.Choice` and
  `click.testing.CliRunner`. A CLI built on the installed package must report
  `click, version 8.5.0` from its `--version` flag.
- The sdist is standalone: building a wheel from the sdist (not from the tree)
  must succeed and produce a wheel whose version is `8.5.0`. Record that
  version in the proof file.
- No library source file may be modified. The code in your wheel must be
  byte-for-byte the upstream code in the checkout; the verifier samples this.
  If you conclude that a change to library code is required, you have
  misdiagnosed the defect — stop and re-read the contract.

## Environment facts

- There is no network at trial time. Every tool and dependency is already in
  the image; do not try to download anything, and do not re-clone `/app/src`.
- The build frontend `build` and the project's declared backend `flit_core`
  are installed in the image's Python. Invoke the build with
  `python3 -m build --no-isolation [--sdist] [--wheel] -o <outdir> <source>` so
  the build does not attempt to fetch its build dependencies.
- `pytest` is installed system-wide, and the project's own self-contained test
  suite is at `/app/src/tests` (it downloads nothing). If you create a virtual
  environment with `python3 -m venv --system-site-packages <dir>`, that venv's
  Python can run pytest too. Use the upstream suite as ground truth that your
  release is behaviorally faithful — a release that passes release review
  passes the core files `test_basic.py` and `test_chain.py`.
- `/app` is writable. The agent environment (venvs, dist output) may live
  anywhere under `/app` or `/tmp`.

The interesting part of the job is yours: determining which metadata is
damaged, where it lives, and what the minimal correct repair is.