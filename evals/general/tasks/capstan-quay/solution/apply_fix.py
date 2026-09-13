#!/usr/bin/env python3
"""Apply the upstream fix for hugo issue #11406 to the checked-out tree.

The bug: for a page whose front matter runs to the end of the file, the
main-content byte offset is never recorded (the code recorded it only when
the parser had NOT reached end-of-input), so RawContent() falls back to
offset 0 and returns the whole file — front matter delimiters and keys
included. The fix records the offset unconditionally right after the front
matter block has been consumed: the position of the next parse item is
always a valid body start, and when there is no body the item is at
end-of-input, so the raw-content slice is empty.

Usage: apply_fix.py /app/src
"""
import pathlib
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply_fix.py <repo-root>", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1])
    page = root / "hugolib" / "page.go"
    src = page.read_text()

    old = """			if !next.IsDone() {
				p.source.posMainContent = next.Pos()
			}"""
    new = """			p.source.posMainContent = next.Pos()"""
    if old not in src:
        print("error: the guarded assignment was not found in hugolib/page.go", file=sys.stderr)
        return 1
    if new in src and old not in src.replace("", "", 1):
        # already applied
        print("ok: fix already present")
        return 0
    page.write_text(src.replace(old, new, 1))
    print("ok: applied fix to hugolib/page.go")
    return 0


if __name__ == "__main__":
    sys.exit(main())