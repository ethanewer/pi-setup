"""Hidden case: end-to-end proxy selection for hosts at domain boundaries.

The user-visible symptom is about which hosts end up proxied. These go through
get_environ_proxies (the function Session uses to merge environment proxy
settings) and resolve_proxies (the request-level resolution path), so a fix
that only patches the argument channel would fail here.
"""
import pytest

from requests.models import PreparedRequest
from requests.utils import get_environ_proxies, resolve_proxies

PROXY = "http://corp-proxy.internal:3128"


@pytest.fixture(autouse=True)
def proxy_env(monkeypatch):
    # Fix the proxy environment deterministically regardless of what the
    # harness exports into the container.
    for var in ("http_proxy", "https_proxy", "ftp_proxy", "all_proxy", "no_proxy"):
        monkeypatch.delenv(var, raising=False)
        monkeypatch.delenv(var.upper(), raising=False)
    monkeypatch.setenv("http_proxy", PROXY)
    monkeypatch.setenv("no_proxy", "example.com")


def test_exact_and_subdomain_hosts_bypass(proxy_env):
    assert get_environ_proxies("http://example.com/") == {}
    assert get_environ_proxies("http://example.com:8080/") == {}
    assert get_environ_proxies("http://sub.example.com/") == {}


def test_suffix_lookalike_is_still_proxied(proxy_env):
    proxies = get_environ_proxies("http://badexample.com/")
    assert proxies.get("http") == PROXY


def test_resolve_proxies_suffix_lookalike(proxy_env):
    req = PreparedRequest()
    req.prepare(method="GET", url="http://badexample.com/")
    resolved = resolve_proxies(req, {"no_proxy": "example.com"}, trust_env=True)
    assert resolved.get("http") == PROXY


def test_dotted_entry_env_channel(monkeypatch):
    for var in ("http_proxy", "https_proxy", "ftp_proxy", "all_proxy", "no_proxy"):
        monkeypatch.delenv(var, raising=False)
        monkeypatch.delenv(var.upper(), raising=False)
    monkeypatch.setenv("http_proxy", PROXY)
    monkeypatch.setenv("NO_PROXY", ".internal.example")
    assert get_environ_proxies("http://internal.example/") == {}
    assert get_environ_proxies("http://srv.internal.example/") == {}
    lookalike = get_environ_proxies("http://xinternal.example/")
    assert lookalike.get("http") == PROXY