from semgrep.meta import get_url_from_sstp_url


def test_azure_without_user_keeps_git_segment():
    url = "https://dev.azure.com/org/My%20Project/_git/repo"
    assert get_url_from_sstp_url(url) == "https://dev.azure.com/org/My%20Project/_git/repo"


def test_azure_remote_with_git_suffix_keeps_git_segment():
    url = "https://test@dev.azure.com/test/TestName/_git/Core.Thing.git"
    assert get_url_from_sstp_url(url) == "https://dev.azure.com/test/TestName/_git/Core.Thing"