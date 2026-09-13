"""Hidden case: guards around the fix -- every git remote shape that already
worked at the pinned commit must keep producing the same https URL. Inputs
were chosen to be distinct from the upstream regression test's cases.

Drives the same public function (semgrep.meta.get_url_from_sstp_url) as the
upstream regression test.
"""

import pytest

from semgrep.meta import get_url_from_sstp_url

CASES = [
    # scp-like with no dash at all (parsed by the generic fallback regexes)
    ("git@github.com:semgrep/semgrep", "https://github.com/semgrep/semgrep"),
    # scp-like, trailing .git present
    ("git@host.xz:path/to/repo.git", "https://host.xz/path/to/repo"),
    # explicit ssh protocol with a port
    # (the port is not part of the rebuilt https URL)
    ("ssh://git@host.xz:2222/path/to/repo.git", "https://host.xz/path/to/repo"),
    # https stays https, .git stripped
    ("https://github.com/semgrep/semgrep", "https://github.com/semgrep/semgrep"),
    ("https://example.org/a/b/project.git", "https://example.org/a/b/project"),
    # tilde home-dir owner form
    ("git@host.xz:~user/path/to/repo.git", "https://host.xz/~user/path/to/repo"),
    # Azure DevOps style URL (azure_git_dir handling) stays intact
    (
        "https://test@dev.azure.com/test/TestName/_git/Core.Thing",
        "https://dev.azure.com/test/TestName/_git/Core.Thing",
    ),
]


@pytest.mark.parametrize(("url", "expected"), CASES)
def test_working_url_shapes_are_preserved(url: str, expected: str) -> None:
    assert get_url_from_sstp_url(url) == expected