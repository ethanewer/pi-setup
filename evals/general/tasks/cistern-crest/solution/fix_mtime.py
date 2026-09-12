#!/usr/bin/env python3
"""Apply the _mtime_meta fix to gallery_dl/postprocessor/mtime.py.

The buggy run() returns early when the raw metadata value is None, leaving the
previous file's _mtime_meta in the shared metadata dict, and treats the
NullDatetime 'no date' sentinel as a real datetime, producing a year-0001
timestamp.  The fix always assigns _mtime_meta (None for missing/falsy/invalid
values) using a truthiness check.  Idempotent; exits non-zero if the expected
snippets are not all present and applied.
"""

import sys
from pathlib import Path

BUGGY = '''    def run(self, pathfmt):
        mtime = self._get(pathfmt.kwdict)
        if mtime is None:
            return

        pathfmt.kwdict["_mtime_meta"] = (
            dt.to_ts(mtime)
            if isinstance(mtime, dt.datetime) else
            text.parse_int(mtime)
        )
'''

FIXED = '''    def run(self, pathfmt):
        if mtime := self._get(pathfmt.kwdict):
            if isinstance(mtime, dt.datetime):
                mtime = dt.to_ts(mtime)
            else:
                mtime = text.parse_int(mtime)
        else:
            mtime = None
        pathfmt.kwdict["_mtime_meta"] = mtime
'''


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1
                else "/app/src/gallery_dl/postprocessor/mtime.py")
    src = path.read_text()
    if FIXED in src:
        print("already fixed:", path)
        return 0
    if BUGGY not in src:
        print("BUGGY run() snippet not found in", path, file=sys.stderr)
        return 1
    path.write_text(src.replace(BUGGY, FIXED))
    print("patched", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())