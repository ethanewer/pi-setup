"""Hidden case: scp-like git remotes (no protocol prefix, no trailing ".git")
with dashes in the organisation or repository name must convert to https.

Exercises the same code path as the upstream regression test
(test_get_url_from_sstp_url) but from hosts and paths that test does not
use. All expectations were measured against the repaired tree; on the buggy
tree every case here returns the raw scp form instead.
"""

import pytest

from semgrep.meta import get_url_from_sstp_url

CASES = [
    # dash in the organisation name
    (
        "git@vcs.somecorp.example:platform-eng/core-services",
        "https://vcs.somecorp.example/platform-eng/core-services",
    ),
    # dashes in both organisation and repository name
    (
        "git@gitlab.example.com:data-team/etl-pipelines",
        "https://gitlab.example.com/data-team/etl-pipelines",
    ),
    # nested (subgroup) path with dashes in every segment
    (
        "git@code.example.internal:org-a/sub-group-b/repo-c",
        "https://code.example.internal/org-a/sub-group-b/repo-c",
    ),
    # single-segment owner with dashes
    (
        "git@bitbucket.example.org:team-x/awesome-tool",
        "https://bitbucket.example.org/team-x/awesome-tool",
    ),
    # repo name containing a dot, no .git prefix
    (
        "git@code.example.internal:qa-org/release-1.0",
        "https://code.example.internal/qa-org/release-1.0",
    ),
]


@pytest.mark.parametrize(("url", "expected"), CASES)
def test_scp_dash_urls_convert_to_https(url: str, expected: str) -> None:
    assert get_url_from_sstp_url(url) == expected