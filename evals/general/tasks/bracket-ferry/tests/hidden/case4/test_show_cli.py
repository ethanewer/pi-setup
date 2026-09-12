"""Hidden case 4: the real `pip show` command against a live legacy dist.

The upstream regression test drives print_results directly with synthetic
records. This case goes through the distribution discovery machinery too:
it fabricates an installed distribution whose dist-info METADATA file has no
Metadata-Version header, puts it on sys.path, and runs the checkout's actual
`pip show` CLI as a subprocess. A fix that only papered over the printing
path (or that only handled synthetic records) fails here because the full
command must discover, format and print the package without crashing.
"""
from __future__ import annotations

import os
import subprocess
import sys

SRC = "/app/src/src"


def test_pip_show_cli_survives_missing_metadata_version(tmp_path) -> None:
    dist_info = tmp_path / "clumsy_pkg-2.0.dist-info"
    dist_info.mkdir()
    (dist_info / "METADATA").write_text(
        "Name: clumsy-pkg\nVersion: 2.0\nSummary: legacy metadata, no version\n",
        encoding="utf-8",
    )

    env = dict(os.environ)
    env["PYTHONPATH"] = SRC + os.pathsep + str(tmp_path)

    proc = subprocess.run(
        [sys.executable, "-m", "pip", "show", "clumsy-pkg"],
        capture_output=True,
        text=True,
        env=env,
        timeout=180,
    )

    combined = proc.stdout + proc.stderr
    assert proc.returncode == 0, (
        f"pip show exited {proc.returncode}:\n{combined}"
    )
    assert "Name: clumsy-pkg" in combined
    assert "Version: 2.0" in combined
    assert "Summary: legacy metadata, no version" in combined
    assert "Traceback" not in combined
    assert "ValueError" not in combined


def test_pip_show_with_metadata_version_still_shows_expression(tmp_path) -> None:
    """A package WITH a modern Metadata-Version must keep its expression line."""
    dist_info = tmp_path / "smart_pkg-1.0.dist-info"
    dist_info.mkdir()
    (dist_info / "METADATA").write_text(
        "Metadata-Version: 2.4\n"
        "Name: smart-pkg\n"
        "Version: 1.0\n"
        "License-Expression: Apache-2.0\n",
        encoding="utf-8",
    )

    env = dict(os.environ)
    env["PYTHONPATH"] = SRC + os.pathsep + str(tmp_path)

    proc = subprocess.run(
        [sys.executable, "-m", "pip", "show", "smart-pkg"],
        capture_output=True,
        text=True,
        env=env,
        timeout=180,
    )

    combined = proc.stdout + proc.stderr
    assert proc.returncode == 0, (
        f"pip show exited {proc.returncode}:\n{combined}"
    )
    assert "License-Expression: Apache-2.0" in combined
    assert "License: " not in combined
    assert "Traceback" not in combined