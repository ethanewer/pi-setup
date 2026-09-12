#!/usr/bin/env python3
"""Verifier-side contract probe for cistern-berth.

Lives under /tests (mounted fresh at verifier time; the agent cannot modify
it), so the bytes here are trustworthy. The verifier executes this file with
`python3 -S` and PYTHONPATH=/app/src:<site-packages>, which disables site
initialisation entirely: any sitecustomize/usercustomize/.pth wrapper an
agent planted is inert, and the only importable aiohttp is the real source
tree at /app/src. This probe therefore asserts the observable contract
against the actual bytes of the clone -- a wrapper cannot fake it.

The assertions mirror the task contract:

  1. the task reproducer terminates and parses 'Forwarded: ; a' to {};
  2. every authored hidden-case input terminates and parses to the
     expected dict (same code path, inputs the upstream regression test
     does not use);
  3. a multi-header-line request with a trailing bad element on one line
     parses all lines.

At the FIXED tree this exits 0 printing the results. On the buggy parent
tree it hangs forever on the very first access (the exact bug), so a caller
can use `timeout` to detect the bug.

"""
import inspect
import sys

import aiohttp
import aiohttp.web_request
import aiohttp.test_utils as tu
import multidict

# The module the grading exercises must literally be the clone's file. Under
# -S with PYTHONPATH=/app/src there is nowhere else aiohttp can come from,
# but assert it anyway so a planted replacement outside the clone fails here.
_src = inspect.getsourcefile(aiohttp.web_request)
assert _src is not None and _src.startswith("/app/src/"), f"web_request not from clone: {_src}"
print("probe: aiohttp.web_request source:", _src)

CIMultiDict = multidict.CIMultiDict
make = tu.make_mocked_request


def one(header):
    req = make("GET", "/", headers=CIMultiDict({"Forwarded": header}))
    return [dict(e) for e in req.forwarded]


def main():
    # 1) task reproducer
    assert one("; a") == [{}], one("; a")
    print("probe: repro '; a' -> {} (terminates)")

    # 2) hidden-case inputs: trailing empty/malformed elements
    expected = [
        ("for=1.2.3.4; ;a", [{"for": "1.2.3.4"}]),
        ("for=_real;x", [{"for": "_real"}]),
        ("for=_real; \t", [{"for": "_real"}]),
        ('for="a;b"; somebody', [{"for": "a;b"}]),
        ("for=1.2.3.4; ; ; a", [{"for": "1.2.3.4"}]),
    ]
    for header, exp in expected:
        got = one(header)
        assert got == exp, (header, got, exp)
    print("probe: hidden-case inputs terminate and parse as expected")

    # 3) multi-header-line requests (bad tail on first line, on second
    #    line, and after several valid pairs)
    headers = CIMultiDict()
    headers.add("Forwarded", "for=1.2.3.4; ;a")
    headers.add("Forwarded", "for=_real")
    req = make("GET", "/", headers=headers)
    got = [dict(e) for e in req.forwarded]
    assert got == [{"for": "1.2.3.4"}, {"for": "_real"}], got

    headers = CIMultiDict()
    headers.add("Forwarded", "for=_real")
    headers.add("Forwarded", "for=9.9.9.9; x")
    req = make("GET", "/", headers=headers)
    got = [dict(e) for e in req.forwarded]
    assert got == [{"for": "_real"}, {"for": "9.9.9.9"}], got

    headers = CIMultiDict()
    headers.add("Forwarded", "for=_one; for=_two; z")
    headers.add("Forwarded", "for=_three")
    req = make("GET", "/", headers=headers)
    got = [dict(e) for e in req.forwarded]
    assert got == [{"for": "_two"}, {"for": "_three"}], got
    print("probe: multi-header requests parse all lines")
    print("CONTRACT OK")


if __name__ == "__main__":
    main()