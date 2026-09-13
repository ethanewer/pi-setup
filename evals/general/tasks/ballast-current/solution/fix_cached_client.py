#!/usr/bin/env python3
"""Apply the minimal upstream fix for the ballast-current bug.

In DataWithCachePolicy::deserialize_cache_policy_len, the guard that rejects
an out-of-bounds cache policy length is

    if bytes.len() < len_usize + 8 {

which itself overflows when the 8-byte trailing length marker decodes to
usize::MAX (a mangled cache file whose last bytes are all 0xFF): len_usize
+ 8 wraps to 7, the guard never fires, and the subsequent slicing panics
with `attempt to add with overflow`. The fix compares the declared policy
length against the number of bytes before the trailing length marker, so the
check cannot overflow and malformed entries take the existing ArchiveRead
error path.

Usage: fix_cached_client.py /app/src/crates/uv-client/src/cached_client.rs
"""
import sys

BUGGY = "        if bytes.len() < len_usize + 8 {"
FIXED = "        if len_usize > cache_policy_len_start {"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_cached_client.py <path-to-cached_client.rs>")
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if BUGGY not in text:
        # Already fixed (or something unexpected is in the tree).
        if FIXED in text:
            print("already patched; nothing to do")
            return 0
        print(f"ERROR: the overflowing length check was not found in "
              f"{path}; refusing to patch", file=sys.stderr)
        return 1
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text.replace(BUGGY, FIXED, 1))
    print("patched: cache policy length check can no longer overflow")
    return 0


if __name__ == "__main__":
    sys.exit(main())