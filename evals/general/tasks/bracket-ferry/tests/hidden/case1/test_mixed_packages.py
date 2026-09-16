"""Hidden case 1: several packages of mixed metadata age in one call.

The upstream regression test calls print_results with exactly one package at
a time. This case feeds legacy (no Metadata-Version) and modern (2.4) package
records into a single call and checks the inter-package separator and that
each package gets the license line its own metadata version selects.
"""
from __future__ import annotations

import logging

import pytest

from pip._internal.commands.show import _PackageInfo, print_results


def _pkg(
    name: str,
    metadata_version: str,
    license_text: str,
    license_expression: str,
) -> _PackageInfo:
    return _PackageInfo(
        name=name,
        version="1.0",
        location=f"/loc/{name}",
        editable_project_location=None,
        requires=[],
        required_by=[],
        installer="pip",
        metadata_version=metadata_version,
        classifiers=[],
        summary="",
        homepage="",
        project_urls=[],
        author="",
        author_email="",
        license=license_text,
        license_expression=license_expression,
        entry_points=[],
        files=None,
    )


def test_mixed_metadata_versions_in_one_call(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO)

    packages = [
        _pkg("legacy", "", "BSD-3-Clause", "MIT OR Apache-2.0"),
        _pkg("modern", "2.4", "BSD-3-Clause", "Apache-2.0"),
    ]

    # Must not raise: the whole point of the fix.
    assert print_results(packages, list_files=False, verbose=False)

    messages = [record.getMessage() for record in caplog.records]
    assert "Name: legacy" in messages
    assert "Name: modern" in messages

    separators = [i for i, m in enumerate(messages) if m == "---"]
    assert len(separators) == 1, "expected exactly one --- separator"
    # Every field of the first package precedes the separator; the second
    # package's fields follow it.
    first, second = messages[: separators[0]], messages[separators[0] + 1 :]

    assert "License: BSD-3-Clause" in first
    assert "License-Expression: MIT OR Apache-2.0" not in first
    assert "License-Expression: Apache-2.0" in second
    assert "License: BSD-3-Clause" not in second
    assert "Version: 1.0" in first
    assert "Location: /loc/modern" in second