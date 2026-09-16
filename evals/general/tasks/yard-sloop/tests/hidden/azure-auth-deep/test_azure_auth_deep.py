from semgrep.meta import get_url_from_sstp_url


def test_azure_deep_owner_keeps_git_segment():
    url = "https://org@dev.azure.com/team/sub/proj/_git/repo"
    assert get_url_from_sstp_url(url) == "https://dev.azure.com/team/sub/proj/_git/repo"


def test_azure_user_pass_auth_dotted_repo_name():
    url = "https://user:pass@dev.azure.com/org/project/_git/repo.x"
    assert get_url_from_sstp_url(url) == "https://dev.azure.com/org/project/_git/repo.x"