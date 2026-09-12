#!/usr/bin/env python3
"""Apply the upstream fix for httpx issue #2998 to a checkout of httpx.

HTTPX Response.iter_text()/aiter_text() yielded a spurious trailing empty
string for streamed bodies: TextChunker.decode() returned [''] when fed the
final empty decoder flush, because the un-chunked path was a bare
'return [content]'.  The fix returns an empty list when the input text is
empty, exactly as the chunked path already did.  Idempotent; exits non-zero if
the expected TextChunker snippet is not present and applied.
"""

import sys
from pathlib import Path

OLD = """    def decode(self, content: str) -> typing.List[str]:
        if self._chunk_size is None:
            return [content]
"""

NEW = """    def decode(self, content: str) -> typing.List[str]:
        if self._chunk_size is None:
            return [content] if content else []
"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_textchunker.py PATH/httpx/_decoders.py", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if NEW in src and OLD not in src:
        print("httpx/_decoders.py already carries the fix")
        return 0
    if src.count(OLD) != 1:
        print(
            "unexpected _decoders.py: expected exactly one bare TextChunker "
            "'return [content]' to replace",
            file=sys.stderr,
        )
        return 1
    path.write_text(src.replace(OLD, NEW), encoding="utf-8")
    print("applied TextChunker.decode fix to %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())