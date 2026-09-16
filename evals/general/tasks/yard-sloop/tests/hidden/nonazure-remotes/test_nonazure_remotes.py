from semgrep.meta import get_url_from_sstp_url


def test_gitlab_deep_group_unaffected():
    url = "https://gitlab.com/example/group2/group3/test-case.git"
    assert get_url_from_sstp_url(url) == "https://gitlab.com/example/group2/group3/test-case"


def test_github_unaffected():
    url = "https://github.com/torvalds/linux.git"
    assert get_url_from_sstp_url(url) == "https://github.com/torvalds/linux"


def test_ssh_protocol_normalised_without_git_segment():
    url = "ssh://git@gitlab.com/group/sub.git"
    assert get_url_from_sstp_url(url) == "https://gitlab.com/group/sub"


def test_scp_like_remote_without_git_segment():
    url = "git@github.com:user/repo.git"
    assert get_url_from_sstp_url(url) == "https://github.com/user/repo"