"""End-to-end hidden case: get_project_url() must strip the credentials that
GitLab CI/CD injects into the remote URL, in real throwaway git repos whose
hosts and token styles the upstream regression test does not use.

Nothing here touches the network: git only reads its own configuration.
"""
import os
import subprocess
import tempfile

from semgrep.git import get_project_url

_CASES = [
    # (remote URL as configured, expected cleaned URL)
    # GitLab CI job token (glcbt-...) on a second-level host without a path
    # beyond the project, as GitLab >=15.0 injects it
    (
        "https://gitlab-ci-token:glcbt-R4nd0mPlusAndUnderscores@gitlab.engineering.example.net/team/project",
        "https://gitlab.engineering.example.net/team/project",
    ),
    # GitLab personal access token style (oauth2/glpat-...)
    (
        "https://oauth2:glpat-ABC123xyz456@gitlab.com/somewhere/else/project.git",
        "https://gitlab.com/somewhere/else/project.git",
    ),
    # self-hosted GitLab on a non-default port, deeper repo path
    (
        "https://gitlab-ci-token:glcbt-abcdefghijklmnopqrstuvwxyz0123456789@gitlab.staging.example.com:8443/a/b/c/d.git",
        "https://gitlab.staging.example.com:8443/a/b/c/d.git",
    ),
]


def _repo_with_origin(url):
    d = tempfile.mkdtemp(prefix="pubrepo-")
    subprocess.check_call(["git", "init", "-q", d])
    subprocess.check_call(["git", "remote", "add", "origin", url], cwd=d)
    return d


def test_project_url_credentials_stripped():
    for i, (url, expected) in enumerate(_CASES):
        d = _repo_with_origin(url)
        old = os.getcwd()
        try:
            os.chdir(d)
            got = get_project_url()
        finally:
            os.chdir(old)
        assert got == expected, (
            f"case {i}: remote {url!r} -> {got!r}, expected {expected!r}"
        )