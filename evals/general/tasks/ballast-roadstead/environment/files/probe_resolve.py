#!/usr/bin/env python3
"""Visible reproducer for the ``poetry debug resolve`` marker crash.

Emulates what ``poetry debug resolve <package>`` does when the resolved
package is restricted to certain environments (here: to ``win32`` only),
using the exact in-memory test-repository machinery the project's own command
tests use, so it runs fully offline.

While the bug is present it crashes with ``IndexError: list assignment index
out of range`` right after printing the resolution summary -- the same
traceback a user typing the real command gets. After the bug is fixed it
prints the marked package with its environment marker as a third column and
exits 0.
"""
from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

# The editable install resolves to the checked-out tree at /app/src, and the
# project's own test helpers (tests/helpers.py) live in that tree too.
sys.path.insert(0, "/app/src")
os.environ.setdefault("COLUMNS", "80")

from cleo.io.null_io import NullIO  # noqa: E402
from cleo.testers.command_tester import CommandTester  # noqa: E402
from poetry.core.version.markers import parse_marker  # noqa: E402
from poetry.factory import Factory  # noqa: E402
from poetry.repositories.repository_pool import RepositoryPool  # noqa: E402
from tests.helpers import PoetryTestApplication  # noqa: E402
from tests.helpers import TestRepository  # noqa: E402
from tests.helpers import get_package  # noqa: E402

PROJECT_TOML = """\
[tool.poetry]
name = "probe-demo"
version = "0.1.0"
description = "minimal project used by the debug resolve reproducer"

[tool.poetry.dependencies]
python = "^3.9"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
"""


def build_tester() -> CommandTester:
    project_dir = Path(tempfile.mkdtemp(prefix="probe-project-"))
    (project_dir / "pyproject.toml").write_text(PROJECT_TOML, encoding="utf-8")

    poetry = Factory().create_poetry(project_dir)

    # In-memory package repository: a package that only supports win32.
    repo = TestRepository(name="probe")
    pkg = get_package("pathlib2", "2.3.0")
    pkg.marker = parse_marker('sys_platform == "win32"')
    repo.add_package(pkg)

    pool = RepositoryPool()
    pool.add_repository(repo)
    poetry.set_pool(pool)

    app = PoetryTestApplication(poetry)
    app._load_plugins(NullIO())

    command = app.find("debug resolve")
    tester = CommandTester(command)
    app_io = app.create_io()
    formatter = app_io.output.formatter
    tester.io.output.set_formatter(formatter)
    tester.io.error_output.set_formatter(formatter)
    return tester


def main() -> int:
    tester = build_tester()
    tester.execute("pathlib2")
    out = tester.io.fetch_output()
    sys.stdout.write(out)
    if "IndexError" in out and "Traceback" in out:
        print("\n[probe] BUG PRESENT: debug resolve crashes on a marked package.",
              file=sys.stderr)
        return 1
    print("\n[probe] OK: the marked package is rendered with its marker.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())