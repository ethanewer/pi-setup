"""Hidden case 2: verbose and --files output for a legacy-metadata package.

The upstream regression test only exercises the default (non-verbose,
non-files) rendering of a package whose metadata version is empty. This case
runs the same code path with verbose=True and list_files=True, which walks
the classifier, entry-point, project-URL and file sections the default
render skips, and asserts the empty Metadata-Version is still rendered as an
empty value rather than crashing on it.
"""
from __future__ import annotations

import logging

import pytest

from pip._internal.commands.show import _PackageInfo, print_results


def test_verbose_and_list_files_with_empty_metadata(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO)

    pkg = _PackageInfo(
        name="legacy",
        version="0.9",
        location="/srv/legacy",
        editable_project_location="/srv/legacy-src",
        requires=["dep"],
        required_by=["ui"],
        installer="pip",
        metadata_version="",
        classifiers=["Topic :: Software Development :: Libraries"],
        summary="a package with incomplete metadata",
        homepage="https://example.invalid",
        project_urls=["Homepage, https://example.invalid"],
        author="Someone",
        author_email="someone@example.invalid",
        license="MIT",
        license_expression="",
        entry_points=["console-scripts = legacy:main"],
        files=["legacy/__init__.py", "legacy/core.py "],
    )

    # Must not raise on the empty metadata version.
    assert print_results([pkg], list_files=True, verbose=True)

    messages = [record.getMessage() for record in caplog.records]
    assert "Name: legacy" in messages
    assert "Summary: a package with incomplete metadata" in messages
    # The Metadata-Version header is printed with its (empty) value.
    assert "Metadata-Version: " in messages
    assert "License: MIT" in messages
    assert "License-Expression: " not in messages
    assert "Editable project location: /srv/legacy-src" in messages
    assert "Requires: dep" in messages
    assert "Required-by: ui" in messages
    assert "Installer: pip" in messages
    # The verbose sections are rendered with their entries (indented).
    assert any(
        "Topic :: Software Development :: Libraries" in m for m in messages
    )
    assert any("console-scripts = legacy:main" in m for m in messages)
    assert any("Homepage, https://example.invalid" in m for m in messages)
    # --files renders the declared files, trailing whitespace stripped.
    assert "Files:" in messages
    assert any("legacy/core.py" in m for m in messages)
    assert not any(m.endswith("legacy/core.py ") for m in messages)