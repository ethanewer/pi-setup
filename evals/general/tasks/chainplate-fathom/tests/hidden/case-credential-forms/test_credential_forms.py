"""Direct hidden case: clean_project_url() contract vectors the upstream
regression test does not cover. Expectations were computed from the exact
upstream implementation (urlsplit + re.sub('^.*:.*@(.+)', r'\\1', netloc)),
so any fix that passes this and the golden test behaves like upstream.
"""
from semgrep.git import clean_project_url

_CASES = [
    # (input URL, expected output)
    # password containing an unencoded '@'
    ("https://user:p@ss@host.example.org/a/b", "https://host.example.org/a/b"),
    # percent-encoded special characters in the password, bare IPv4 host
    ("https://user:p%40ss!x@10.0.0.7/private/repo", "https://10.0.0.7/private/repo"),
    # explicit port on host with credentials must keep the port
    ("https://user:token@gitlab.example.com:8443/group/repo", "https://gitlab.example.com:8443/group/repo"),
    # GitHub-style PAT userinfo
    ("https://x-access-token:ghp_AbCdEf123456@github.example.com/acme/private.git", "https://github.example.com/acme/private.git"),
    # already-clean URLs are returned unchanged
    ("https://github.com/semgrep/semgrep.git", "https://github.com/semgrep/semgrep.git"),
    ("https://gitlab.com/org/other.git", "https://gitlab.com/org/other.git"),
    ("https://host.example.org/plain/path", "https://host.example.org/plain/path"),
    # scp/ssh-style forms are not HTTP basic-auth and stay untouched
    ("ssh://git@host.example:2222/x/y.git", "ssh://git@host.example:2222/x/y.git"),
]


def test_clean_project_url_forms():
    for i, (url, expected) in enumerate(_CASES):
        got = clean_project_url(url)
        assert got == expected, f"case {i}: {url!r} -> {got!r}, expected {expected!r}"