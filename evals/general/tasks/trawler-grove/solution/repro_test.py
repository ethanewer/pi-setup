"""The oracle's failing reproduction for trawler-grove.

Drives the code path the bug lives in exactly the way the project's own
git-backend tests do: mock the system git calls, call the clone fallback
with an explicit plumbing ref, and assert the revision handed to
'git checkout' is the bare branch/tag name.

Against the parent commit this fails: the raw 'refs/heads/main' and
'refs/tags/v1.0' strings are passed to SystemGit.checkout unchanged.
After the fix it passes.
"""
from __future__ import annotations

from pathlib import Path

from poetry.vcs.git.backend import Git
from poetry.vcs.git.backend import GitRefSpec


def test_legacy_clone_strips_refs_heads_prefix(tmp_path: Path, mocker) -> None:
    mocker.patch("poetry.vcs.git.system.SystemGit.clone")
    mock_checkout = mocker.patch("poetry.vcs.git.system.SystemGit.checkout")
    mocker.patch("poetry.vcs.git.backend.Repo")

    target = tmp_path / "repo"
    Git._clone_legacy("https://example.com/repo.git", GitRefSpec(revision="refs/heads/main"), target)

    mock_checkout.assert_called_once_with("main", target)


def test_legacy_clone_strips_refs_tags_prefix(tmp_path: Path, mocker) -> None:
    mocker.patch("poetry.vcs.git.system.SystemGit.clone")
    mock_checkout = mocker.patch("poetry.vcs.git.system.SystemGit.checkout")
    mocker.patch("poetry.vcs.git.backend.Repo")

    target = tmp_path / "repo"
    Git._clone_legacy("https://example.com/repo.git", GitRefSpec(revision="refs/tags/v1.0"), target)

    mock_checkout.assert_called_once_with("v1.0", target)


def test_legacy_clone_passes_plain_revision_through(tmp_path: Path, mocker) -> None:
    mocker.patch("poetry.vcs.git.system.SystemGit.clone")
    mock_checkout = mocker.patch("poetry.vcs.git.system.SystemGit.checkout")
    mocker.patch("poetry.vcs.git.backend.Repo")

    target = tmp_path / "repo"
    Git._clone_legacy("https://example.com/repo.git", GitRefSpec(revision="abc123"), target)

    mock_checkout.assert_called_once_with("abc123", target)