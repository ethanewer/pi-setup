#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Apply the kedge-fairway fix to a gallery-dl checkout.

The bug: HttpDownloader only consulted a parsed Content-Length against the
minsize/maxsize limits; a zero-byte body (Content-Length: 0) fell through and
was downloaded as a successful empty file.  A zero size must now short-circuit:
release the connection, log a WARNING and return False so the file is neither
written nor recorded as a success.

This is the minimal source change that restores the expected behaviour while
keeping every other download path untouched (the downloader's own suite and
the upstream regression test must stay green).
"""
import sys

OLD = """            size = text.parse_int(size, None)
            if size is not None:
"""
NEW = """            size = text.parse_int(size, None)
            if size is not None:
                if not size:
                    self.release_conn(response)
                    self.log.warning("Empty file")
                    return False
"""


def main(path):
    with open(path) as fp:
        source = fp.read()

    if "if not size:" in source:
        print(f"{path}: fix already present")
        return 0

    count = source.count(OLD)
    if count != 1:
        print(f"{path}: expected exactly one match of the size-check block, "
              f"found {count}; refusing to patch", file=sys.stderr)
        return 1

    with open(path, "w") as fp:
        fp.write(source.replace(OLD, NEW, 1))
    print(f"{path}: patch applied")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))