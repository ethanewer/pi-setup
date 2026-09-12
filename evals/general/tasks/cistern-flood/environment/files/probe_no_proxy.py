#!/usr/bin/env python3
"""Probe the current proxy-bypass behaviour at domain boundaries.

Prints the decision should_bypass_proxies makes for representative inputs.
On the buggy tree the first line comes out True (the correct answer is
False: prelocalhost is not localhost), and a dotted entry pinned to a port
fails to match its exact host:port (the correct answer is True).
"""
from requests.utils import should_bypass_proxies

cases = (
    ("http://prelocalhost/", "localhost", "prelocalhost is NOT localhost (correct: False)"),
    ("http://svc.internal:9443/", ".svc.internal:9443", "exact host:port of the dotted entry (correct: True)"),
    ("http://d.o.t/", ".d.o.t", "exact bare host of the dotted entry (correct: True)"),
)
for url, no_proxy, note in cases:
    result = should_bypass_proxies(url, no_proxy=no_proxy)
    print(f"should_bypass_proxies({url!r}, no_proxy={no_proxy!r}) = {result}   # {note}")