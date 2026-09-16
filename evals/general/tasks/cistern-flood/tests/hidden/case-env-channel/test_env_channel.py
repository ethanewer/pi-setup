"""Hidden case: no_proxy read from the environment (NO_PROXY), argument None.

The upstream regression test always passes no_proxy as an argument. This case
drives the same code path through the environment channel that
should_bypass_proxies reads when no_proxy is None: both the greedy-suffix
direction (plain "example.org" vs lookalikes) and dotted / port-pinned entries
are exercised with entries the upstream test does not use.
"""
import pytest

from requests.utils import should_bypass_proxies

NO_PROXY = "example.org, .api.internal, gate.corp:3138"


@pytest.mark.parametrize(
    "url, expected",
    [
        # plain entry: exact host and real subdomains bypass
        ("http://example.org/", True),
        ("http://sub.example.org/", True),
        # hosts that merely end with the entry must NOT bypass
        ("http://badexample.org/", False),
        ("http://badexample.org:8080/", False),
        ("http://xexample.org/", False),
        # port-pinned entry: exact host:port bypasses, nothing else does
        ("http://gate.corp:3138/", True),
        ("http://gate.corp:3139/", False),
        ("http://gate.corp/", False),
        # dotted entry via the environment: bare host and subdomains bypass
        ("http://api.internal/", True),
        ("http://sub.api.internal/", True),
        ("http://xapi.internal/", False),
    ],
)
def test_env_channel_no_proxy(url, expected, monkeypatch):
    monkeypatch.setenv("NO_PROXY", NO_PROXY)
    monkeypatch.delenv("no_proxy", raising=False)
    assert should_bypass_proxies(url, no_proxy=None) is expected