#!/usr/bin/env python3
"""The platform's outbound page fetcher.

Usage:
    python3 /app/puller.py [URL] -o OUT.html

The facility honours an override file at /app/override/proxy.txt: when that file
is present and not blank, its first non-blank line is used as an http/https
proxy for the request. Out-of-the-box that file points the tool at a broken
egress proxy, so every fetch returns a 502 proxy error page. This is the fault
an operator has to diagnose and repair.
"""
import os, sys
import requests


def target():
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        return sys.argv[1]
    return "http://127.0.0.1:9000/page"


def outpath():
    args = sys.argv[1:]
    if "-o" in args:
        return args[args.index("-o") + 1]
    return None


def override_proxy():
    fp = "/app/override/proxy.txt"
    if os.path.exists(fp):
        t = open(fp).read().strip().splitlines()
        if t and t[0].strip():
            return t[0].strip()
    return None


def main():
    url = target()
    out = outpath()
    if not out:
        print("usage: python3 %s [URL] -o OUT" % sys.argv[0])
        sys.exit(2)
    proxy = override_proxy()
    kwargs = {}
    if proxy:
        kwargs["proxies"] = {"http": proxy, "https": proxy}
    try:
        r = requests.get(url, timeout=20, **kwargs)
        r.raise_for_status()
        body = r.content
    except Exception as e:
        print("FETCH_ERROR %s" % e)
        sys.exit(1)
    with open(out, "wb") as f:
        f.write(body)
    print("saved %s %d bytes via proxy=%s" % (out, len(body), proxy or "NONE"))


if __name__ == "__main__":
    main()