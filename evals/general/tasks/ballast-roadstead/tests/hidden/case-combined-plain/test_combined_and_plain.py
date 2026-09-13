"""Hidden case: markers the upstream regression test does not use (2 of 2).

Exercises the same ``debug resolve`` rendering path with a combined
environment-marker expression and a ``platform_machine`` marker -- shapes the
upstream regression test never uses -- and, critically, with a plain package
that carries no environment marker, proving the row keeps exactly two columns
(no spurious empty third column is appended when there is no marker to show).

With the upstream bug present every one of these resolutions raises
``IndexError: list assignment index out of range`` as soon as the marked
package is rendered; only the plain-package resolution completes.
"""
from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, "/app/src")
os.environ.setdefault("COLUMNS", "80")

import pytest  # noqa: E402
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
name = "hidden-demo"
version = "0.1.0"
description = "hidden-case project"

[tool.poetry.dependencies]
python = "^3.9"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
"""


def build_tester(pkgs) -> CommandTester:
    """pkgs: iterable of (name, version, marker or None)."""
    project_dir = Path(tempfile.mkdtemp(prefix="hidden-project-"))
    (project_dir / "pyproject.toml").write_text(PROJECT_TOML, encoding="utf-8")

    poetry = Factory().create_poetry(project_dir)

    repo = TestRepository(name="hidden")
    for name, version, marker in pkgs:
        pkg = get_package(name, version)
        if marker is not None:
            pkg.marker = parse_marker(marker)
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


def resolve(tester: CommandTester, package: str) -> str:
    tester.execute(package)
    return tester.io.fetch_output()


def test_combined_marker_shown_as_third_column() -> None:
    tester = build_tester(
        [("functools32", "3.2.3.post2", 'sys_platform == "win32" and python_version < "3.5"')]
    )
    expected = (
        "Resolving dependencies...\n"
        "\n"
        "Resolution results:\n"
        "\n"
        'functools32 3.2.3.post2 sys_platform == "win32" and python_version < "3.5"\n'
    )
    assert resolve(tester, "functools32") == expected


def test_platform_machine_marker_shown_as_third_column() -> None:
    tester = build_tester([("contextlib2", "21.6.0", 'platform_machine == "arm64"')])
    expected = (
        "Resolving dependencies...\n"
        "\n"
        "Resolution results:\n"
        "\n"
        'contextlib2 21.6.0 platform_machine == "arm64"\n'
    )
    assert resolve(tester, "contextlib2") == expected


def test_plain_package_row_keeps_exactly_two_columns() -> None:
    """A package with no environment marker prints exactly two columns."""
    tester = build_tester(
        [
            ("contextlib2", "21.6.0", 'platform_machine == "arm64"'),
            ("docopt", "0.6.2", None),
        ]
    )
    plain = resolve(tester, "docopt")
    assert plain == (
        "Resolving dependencies...\n"
        "\n"
        "Resolution results:\n"
        "\n"
        "docopt 0.6.2\n"
    )
    # the marked package still renders with its marker in the same repo
    marked = resolve(tester, "contextlib2")
    assert marked.endswith('contextlib2 21.6.0 platform_machine == "arm64"\n')