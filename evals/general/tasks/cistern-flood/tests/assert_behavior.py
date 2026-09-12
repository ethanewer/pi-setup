#!/usr/bin/env python3
"""Direct behavioral assertions for the cistern-flood verifier.

These are intentionally NOT routed through pytest: they probe the observable
proxy-bypass semantics at domain boundaries directly through the library, so
a pytest shim (untracked /app/src/pytest.py, or a rewritten site-packages
pytest) cannot spoof them into passing while the source bug remains.

The assertions mirror the upstream regression test extracted into
/opt/golden/ and add inputs the upstream test does not use (dotted and
port-pinned entries through the argument channel, the NO_PROXY environment
channel, and the end-to-end get_environ_proxies path).
"""
import os

from requests.utils import get_environ_proxies, should_bypass_proxies

failures: list[str] = []


def check(label: str, got: object, want: object) -> None:
    if got == want:
        return
    failures.append(f"{label}: expected {want!r}, got {got!r}")


# --- argument channel ---------------------------------------------------------
# greedy-suffix direction: a host that merely ends with the entry must not
# bypass proxies (the upstream regression test's failing case at parent).
check("prelocalhost vs localhost",
      should_bypass_proxies("http://prelocalhost/", no_proxy="localhost"), False)
check("badexample.com vs example.com",
      should_bypass_proxies("http://badexample.com/", no_proxy="example.com"), False)
# genuine subdomains still bypass
check("sub.example.com vs example.com",
      should_bypass_proxies("http://sub.example.com/", no_proxy="example.com"), True)
# port-pinned dotted entry: exact host:port must match (fails at parent)
check("svc.internal:9443 vs .svc.internal:9443",
      should_bypass_proxies("http://svc.internal:9443/", no_proxy=".svc.internal:9443"), True)
check("xsvc.internal:9443 vs .svc.internal:9443",
      should_bypass_proxies("http://xsvc.internal:9443/", no_proxy=".svc.internal:9443"), False)
# dotted entry matches the bare host too
check("d.o.t vs .d.o.t",
      should_bypass_proxies("http://d.o.t/", no_proxy=".d.o.t"), True)

# --- NO_PROXY environment channel --------------------------------------------
old_no_proxy = os.environ.pop("NO_PROXY", None)
os.environ["NO_PROXY"] = "example.org, .api.internal, gate.corp:3138"
try:
    check("env: example.org exact",
          should_bypass_proxies("http://example.org/", no_proxy=None), True)
    check("env: badexample.org lookalike",
          should_bypass_proxies("http://badexample.org/", no_proxy=None), False)
    check("env: api.internal dotted-entry bare host",
          should_bypass_proxies("http://api.internal/", no_proxy=None), True)
    check("env: xapi.internal lookalike",
          should_bypass_proxies("http://xapi.internal/", no_proxy=None), False)
    check("env: gate.corp:3138 exact port",
          should_bypass_proxies("http://gate.corp:3138/", no_proxy=None), True)
    check("env: gate.corp:3139 wrong port",
          should_bypass_proxies("http://gate.corp:3139/", no_proxy=None), False)
finally:
    if old_no_proxy is None:
        del os.environ["NO_PROXY"]
    else:
        os.environ["NO_PROXY"] = old_no_proxy

# --- end-to-end path ----------------------------------------------------------
old_env: dict[str, str | None] = {}
for var in ("http_proxy", "https_proxy", "ftp_proxy", "all_proxy", "no_proxy"):
    old_env[var] = os.environ.pop(var, None)
    old_env[var.upper()] = os.environ.pop(var.upper(), None)
try:
    os.environ["http_proxy"] = "http://corp-proxy.internal:3128"
    os.environ["no_proxy"] = "example.com"
    check("e2e: badexample.com still proxied",
          get_environ_proxies("http://badexample.com/").get("http"),
          "http://corp-proxy.internal:3128")
    check("e2e: example.com bypassed", get_environ_proxies("http://example.com/"), {})
    check("e2e: sub.example.com bypassed", get_environ_proxies("http://sub.example.com/"), {})
finally:
    for var, val in old_env.items():
        if val is None:
            os.environ.pop(var, None)
        else:
            os.environ[var] = val

if failures:
    for line in failures:
        print("FAIL:", line)
    raise SystemExit(1)
print("behavior assertions passed")
raise SystemExit(0)