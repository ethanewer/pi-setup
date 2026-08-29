#!/usr/bin/env python3
"""fetch.py — fetch a URL and save its exact bytes to an output file.

Usage:
    python3 /app/fetch.py URL [OUTFILE]

OUTFILE defaults to /app/fetch_result.html. The output file is ONLY written when
the fetch succeeds; on a dead/unreachable URL or a malformed URL the script exits
nonzero and does NOT create, truncate or modify the output file.
"""
import sys
import urllib.request


def main(argv):
    if len(argv) < 1 or len(argv) > 2:
        sys.stderr.write("usage: python3 /app/fetch.py URL [OUTFILE]\n")
        return 2
    url = argv[0]
    out = argv[1] if len(argv) == 2 else "/app/fetch_result.html"

    if not url.lower().startswith(("http://", "https://")):
        sys.stderr.write("fetch: unsupported URL: %r\n" % url)
        return 3

    try:
        with urllib.request.urlopen(url, timeout=8) as r:
            body = r.read()
    except Exception as e:  # unreachable / timeout / 4xx-5xx / DNS
        sys.stderr.write("fetch: ERROR: %s\n" % e)
        return 1

    # Only on success do we touch the output file (no mutation on failure).
    with open(out, "wb") as f:
        f.write(body)
    sys.stdout.write("fetch: wrote %d bytes to %s\n" % (len(body), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
