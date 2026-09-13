#!/usr/bin/env python3
"""Apply the upstream fix for the out-of-range '@' timestamp panic to fd.

Replaces the overflowing addition in TimeFilter::from_str with the checked
variant so that an out-of-range '@' timestamp yields None and flows through
the existing graceful parse-failure path, exactly as upstream commit
5becb9d52cb532c35b68421075e4d8ee8d6c77cd does.

Usage: fix_time.py /app/src/src/filter/time.rs
"""

import sys

OLD = "            Some(UNIX_EPOCH + Duration::from_secs(timestamp_secs))"
NEW = "            UNIX_EPOCH.checked_add(Duration::from_secs(timestamp_secs))"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path to src/filter/time.rs>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    if NEW in text:
        print("fix already applied; nothing to do")
        return 0
    if text.count(OLD) != 1:
        print(
            f"expected exactly one occurrence of the buggy line, found "
            f"{text.count(OLD)}; refusing to patch",
            file=sys.stderr,
        )
        return 1
    text = text.replace(OLD, NEW)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())