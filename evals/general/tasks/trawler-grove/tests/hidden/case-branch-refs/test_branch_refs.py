"""Hidden case: branch-shaped plumbing refs the upstream regression test does
not use.

The upstream regression test (test_clone_legacy_strips_ref_prefixes)
parametrizes plain 'refs/heads/main', 'refs/tags/v1.0', 'abc123' and 'HEAD'.
These tests drive the same clone-fallback code path from branch refs with
slashes and dots, from the refspec.branch field rather than refspec.revision,
and include a passthrough guard proving plumbing refs that are NOT
refs/heads/ or refs/tags/ (e.g. refs/remotes/...) are not over-stripped.

At the parent commit every refs/heads assert fails: the raw prefixed string
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
    target = Path("/tmp/hidden-branch-repo")
    Git._clone_legacy("https://example.com/repo.git", GitRefSpec(revision=revision), target)
    return mock_checkout.call_args[0][0]


def test_slashy_feature_branch(tmp_path: Path, mocker) -> None:
    assert _clone_legacy_checkout_arg(mocker, "refs/heads/feature/log-attachment") == \
        "feature/log-attachment"


def test_release_branch_with_dot(tmp_path: Path, mocker) -> None:
    assert _clone_legacy_checkout_arg(mocker, "refs/heads/release/2.x") == "release/2.x"


def test_branch_field_also_stripped(tmp_path: Path, mocker) -> None:
    """The refspec.branch field feeds the same revision slot as .revision."""
    mocker.patch("poetry.vcs.git.system.SystemGit.clone")
    mock_checkout = mocker.patch("poetry.vcs.git.system.SystemGit.checkout")
    mocker.patch("poetry.vcs.git.backend.Repo")
    target = tmp_path / "repo"
    Git._clone_legacy(
        "https://example.com/repo.git", GitRefSpec(branch="refs/heads/experiment"), target
    )
    mock_checkout.assert_called_once_with("experiment", target)


def test_remotes_ref_passes_through_unstripped(tmp_path: Path, mocker) -> None:
    """Only refs/heads/ and refs/tags/ are stripped; other plumbing refs stay."""
    assert _clone_legacy_checkout_arg(mocker, "refs/remotes/origin/main") == \
        "refs/remotes/origin/main"