"""Hidden case: markers the upstream regression test does not use (1 of 2).

The upstream regression test covers one package (``pathlib2``) with one marker
(``sys_platform == "win32"``). This case drives the same ``debug resolve``
rendering path with different operating-system and interpreter markers --
``darwin`` and a ``python_version`` range -- and asserts the exact rendered
output each time.

These cases only pass when the marker is appended as a third output column;
with the upstream bug present the command raises ``IndexError: list assignment
index out of range``.
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


def test_darwin_marker_shown_as_third_column() -> None:
    tester = build_tester([("six", "1.16.0", 'sys_platform == "darwin"')])
    expected = (
        "Resolving dependencies...\n"
        "\n"
        "Resolution results:\n"
        "\n"
        'six 1.16.0 sys_platform == "darwin"\n'
    )
    assert resolve(tester, "six") == expected


def test_python_version_marker_shown_as_third_column() -> None:
    tester = build_tester([("enum34", "1.1.10", 'python_version < "3.4"')])
    expected = (
        "Resolving dependencies...\n"
        "\n"
        "Resolution results:\n"
        "\n"
        'enum34 1.1.10 python_version < "3.4"\n'
    )
    assert resolve(tester, "enum34") == expected


def test_multiple_marked_packages_in_one_repository() -> None:
    tester = build_tester(
        [
            ("six", "1.16.0", 'sys_platform == "darwin"'),
            ("enum34", "1.1.10", 'python_version < "3.4"'),
        ]
    )
    darwin = resolve(tester, "six")
    assert darwin.endswith('six 1.16.0 sys_platform == "darwin"\n')
    pyver = resolve(tester, "enum34")
    assert pyver.endswith('enum34 1.1.10 python_version < "3.4"\n')