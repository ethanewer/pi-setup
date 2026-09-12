#!/usr/bin/env python3
"""Probe for cistern-cable: show what iter_text() yields over a streamed body.

At the pinned (buggy) commit this prints the spurious trailing empty chunk and
exits non-zero. After the fix it prints the clean chunk list and exits 0.
"""

import sys

import httpx


def main() -> int:
    response = httpx.Response(200, content=iter((b"Hello,", b" world!")))
    chunks = list(response.iter_text())
    print("iter_text chunks:", chunks)
    if "" in chunks:
        print("SPURIOUS EMPTY TEXT CHUNK PRESENT")
        return 1
    print("OK: no spurious empty chunk")
    return 0


if __name__ == "__main__":
    sys.exit(main())