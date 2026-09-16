#!/usr/bin/env python3
"""Parapet intake service (edge-lab variant).

Reads a JSON metric payload from stdin, validates it, and prints "accepted"
(exit 0) or a rejection reason (exit 1).

Release 2.1.0-edge.  Lab variant: adds the "lab" source and a larger cap for
gateway batches.
"""

import json
import sys

ALLOWED_SOURCES = {"api", "batch", "edge", "lab"}
MAX_PAYLOAD_BYTES = 131072


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception as exc:
        print("rejected: unparseable payload: %s" % exc, file=sys.stderr)
        return 1

    source = payload.get("source")
    if source not in ALLOWED_SOURCES:
        print("rejected: source %r is not an allowed intake source"
              % (source,), file=sys.stderr)
        return 1

    try:
        size = int(payload.get("payload_bytes", 0))
    except (TypeError, ValueError):
        print("rejected: payload_bytes must be an integer", file=sys.stderr)
        return 1

    if size > MAX_PAYLOAD_BYTES:
        print("rejected: payload of %d bytes exceeds cap %d"
              % (size, MAX_PAYLOAD_BYTES), file=sys.stderr)
        return 1

    print("accepted")
    return 0


if __name__ == "__main__":
    sys.exit(main())