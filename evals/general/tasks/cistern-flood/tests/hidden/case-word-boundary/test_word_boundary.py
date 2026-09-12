"""Hidden case: suffix-lookalike hosts and dotted/port-pinned entries.

Exercises should_bypass_proxies through the no_proxy ARGUMENT channel with
entry shapes the upstream regression test does not use (the upstream test
passes no_proxy="localhost, anotherdomain.com, newdomain.com:1234, .d.o.t"
with a fixed url set; here the entries and urls are entirely different, and
the port-pinned and dotted-entry cases are pushed further).
"""
import pytest

from requests.utils import should_bypass_proxies

NO_PROXY = "example.com, corp.internal:8443, .auth.internal, .svc.internal:9443"


@pytest.mark.parametrize(
    "url, expected",
    [
        # exact hostname matches
        ("http://example.com/", True),
        ("http://example.com:80/", True),
        # genuine subdomains of a plain entry
        ("http://sub.example.com/", True),
        ("http://deep.sub.example.com:8080/", True),
        # hosts that merely end with the entry must NOT bypass
        ("http://badexample.com/", False),
        ("http://xexample.com/", False),
        ("http://evil-example.com:8080/", False),
        # port-pinned entry: exact host:port bypasses, nothing else does
        ("http://corp.internal:8443/", True),
        ("http://corp.internal:8444/", False),
        ("http://corp.internal/", False),
        # dotted entry: bare host and subdomains bypass
        ("http://auth.internal/", True),
        ("http://auth.internal:443/", True),
        ("http://api.auth.internal/", True),
        ("http://xauth.internal/", False),
        # dotted entry with port: exact host:port and its subdomains bypass
        ("http://svc.internal:9443/", True),
        ("http://xsvc.internal:9443/", False),
    ],
)
def test_no_proxy_domain_boundaries(url, expected):
    assert should_bypass_proxies(url, no_proxy=NO_PROXY) is expected