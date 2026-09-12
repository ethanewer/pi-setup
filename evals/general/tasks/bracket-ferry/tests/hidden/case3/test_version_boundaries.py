"""Hidden case 3: metadata-version boundary values around the 2.4 switch.

The upstream regression test checks two specific versions ("" and "2.4").
This case attacks the version-dependent license-line switch from the rest of
the input space: a single-part version, versions older and newer than 2.4,
a three-part 2.4.x, and a 2.4 record whose License-Expression is absent
(which must fall back to the plain License line).
"""
from __future__ import annotations

import logging

import pytest

from pip._internal.commands.show import _PackageInfo, print_results


def _pkg(
    metadata_version: str,
    license_expression: str,
) -> _PackageInfo:
    return _PackageInfo(
        name="boundary",
        version="1.0",
        location="/loc/boundary",
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
        license="MIT",
        license_expression=license_expression,
        entry_points=[],
        files=None,
    )


@pytest.mark.parametrize(
    "metadata_version, license_expression, expected, unexpected",
    [
        # sub-2.4 versions must print the plain License line, never crash.
        ("0", "Apache-2.0", "License: MIT", "License-Expression:"),
        ("1.3", "Apache-2.0", "License: MIT", "License-Expression:"),
        ("2.3", "Apache-2.0", "License: MIT", "License-Expression:"),
        # at/above 2.4 the expression line is printed when present.
        ("2.4", "Apache-2.0", "License-Expression: Apache-2.0", "License: MIT"),
        ("2.4.1", "Apache-2.0", "License-Expression: Apache-2.0", "License: MIT"),
        ("3", "Apache-2.0", "License-Expression: Apache-2.0", "License: MIT"),
        # 2.4 without a License-Expression falls back to the plain line.
        ("2.4", "", "License: MIT", "License-Expression:"),
    ],
)
def test_version_boundaries(
    caplog: pytest.LogCaptureFixture,
    metadata_version: str,
    license_expression: str,
    expected: str,
    unexpected: str,
) -> None:
    caplog.set_level(logging.INFO)

    # Must not raise for any of these metadata version shapes.
    assert print_results(
        [_pkg(metadata_version, license_expression)], list_files=False, verbose=False
    )

    messages = [record.getMessage() for record in caplog.records]
    assert expected in messages
    assert not any(unexpected in m for m in messages)