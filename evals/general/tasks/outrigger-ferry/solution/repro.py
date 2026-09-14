#!/usr/bin/env python3
"""Failing reproduction for outrigger-ferry (python-poetry/poetry #10804).

Drives poetry's real Executor through the IsolatedBuildBackendError branch
(the install-failed-during-build path) for a local directory package whose
installer.build-config-settings hold one plain-string setting ("CC": "gcc")
and one list-of-strings setting ("--build-option": ["--one", "--two"]),
prints the remediation pip command poetry assembles, and exits 0 if and
only if the whole string value is rendered as a single
--config-settings flag. On the unfixed code the string value is iterated
per character, so the printed command is per-letter garbage and this
script exits non-zero.

Only the build-backend boundary is stubbed (the same level at which the
project's own tests stub ProjectBuilder.build); the Executor code under
test is 100% real.
"""
import sys
from pathlib import Path

from build import BuildBackendException
from cleo.io.buffered_io import BufferedIO
from poetry.config.config import Config
from poetry.installation.executor import Executor
from poetry.installation.operations import Install
from poetry.core.packages.package import Package
from poetry.repositories.repository_pool import RepositoryPool
from poetry.utils.env import MockEnv
from poetry.utils.isolated_build import IsolatedBuildBackendError


def main() -> int:
    project = Path("/app/src/tests/fixtures/simple_project").resolve()
    if not project.is_dir():
        print(f"fixture directory not found: {project}")
        return 2

    cfg = Config()
    cfg.merge(
        {
            "cache-dir": "/tmp/outrigger-repro/cache",
            "data-dir": "/tmp/outrigger-repro/data",
            "installer": {
                "parallel": False,
                "build-config-settings": {
                    "simple-project": {
                        "CC": "gcc",
                        "--build-option": ["--one", "--two"],
                    },
                },
            },
        }
    )

    error = IsolatedBuildBackendError(
        project,
        BuildBackendException(Exception("build failed"), description="build failed"),
    )

    io = BufferedIO()
    executor = Executor(MockEnv(), RepositoryPool(), cfg, io)
    executor._chef.prepare = lambda *a, **k: (_ for _ in ()).throw(error)

    package = Package(
        "simple-project",
        "1.2.3",
        source_type="directory",
        source_url=project.as_posix(),
    )
    executor.execute([Install(package)])

    output = io.fetch_output()
    print(output)

    ok = True
    if "--config-settings='CC=gcc'" not in output:
        print("MISSING: the whole-string setting 'CC=gcc' must appear as ONE flag")
        ok = False
    if "--config-settings='C=C'" in output:
        print("GARBLED: per-character flags for the string value are present")
        ok = False
    if "--config-settings='--build-option=--one'" not in output:
        print("MISSING: array value item '--build-option=--one'")
        ok = False
    if "--config-settings='--build-option=--two'" not in output:
        print("MISSING: array value item '--build-option=--two'")
        ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())