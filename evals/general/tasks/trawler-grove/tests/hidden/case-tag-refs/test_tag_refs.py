"""Hidden case: tag-shaped plumbing refs the upstream regression test does not
use.

The upstream regression test parametrizes a single plain 'refs/tags/v1.0'.
These tests drive the same clone-fallback code path from tag refs with
pre-release suffixes, dotted versions and date-style names, and from the
refspec.tag field rather than refspec.revision.

At the parent commit every refs/tags assert fails: the raw prefixed string
is handed to checkout. With the fix they pass.
"""
from __future__ import annotations

import sys

sys.path.insert(0, "/app/src/src")

from pathlib import Path

from poetry.vcs.git.backend import Git
from poetry.vcs.git.backend import GitRefSpec


def _clone_legacy_checkout_arg(mocker, revision: str) -> str:
    mocker.patch("poetry.vcs.git.system.SystemGit.clone")
    mock_checkout = mocker.patch("poetry.vcs.git.system.SystemGit.checkout")
    mocker.patch("poetry.vcs.git.backend.Repo")
    target = Path("/tmp/hidden-tag-repo")
    Git._clone_legacy("https://example.com/repo.git", GitRefSpec(revision=revision), target)
    return mock_checkout.call_args[0][0]


def test_prerelease_tag(tmp_path: Path, mocker) -> None:
    assert _clone_legacy_checkout_arg(mocker, "refs/tags/v1.0.0-rc1") == "v1.0.0-rc1"


def test_date_style_tag(tmp_path: Path, mocker) -> None:
    assert _clone_legacy_checkout_arg(mocker, "refs/tags/prod-2024.09.01") == "prod-2024.09.01"


def test_tag_field_also_stripped(tmp_path: Path, mocker) -> None:
    """The refspec.tag field feeds the same revision slot as .revision."""
    mocker.patch("poetry.vcs.git.system.SystemGit.clone")
    mock_checkout = mocker.patch("poetry.vcs.git.system.SystemGit.checkout")
    mocker.patch("poetry.vcs.git.backend.Repo")
    target = tmp_path / "repo"
    Git._clone_legacy(
        "https://example.com/repo.git", GitRefSpec(tag="refs/tags/v9"), target
    )
    mock_checkout.assert_called_once_with("v9", target)


def test_major_minor_tag(tmp_path: Path, mocker) -> None:
    assert _clone_legacy_checkout_arg(mocker, "refs/tags/v2.3.1") == "v2.3.1"