from semgrep.meta import get_url_from_sstp_url


def test_azure_trailing_slash_keeps_git_segment():
    url = "https://test@dev.azure.com/test/TestName/_git/Core.Thing/"
    assert get_url_from_sstp_url(url) == "https://dev.azure.com/test/TestName/_git/Core.Thing"


def test_azure_repo_named_like_project_keeps_git_segment():
    url = "https://bob@dev.azure.com/acme/apps/_git/checkout-page"
    assert get_url_from_sstp_url(url) == "https://dev.azure.com/acme/apps/_git/checkout-page"