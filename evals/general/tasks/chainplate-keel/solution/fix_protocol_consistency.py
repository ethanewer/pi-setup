#!/usr/bin/env python3
"""Apply the minimal upstream fix for the chainplate-keel bug.

checkFileInfoConsistency() in lib/protocol/protocol.go rejected ANY non-file
index entry (directory or symlink) with a nonzero Size field: the shared case
was

    case f.Type != FileInfoTypeFile && f.Size != 0:
        // Only files should have a size
        return errNonFileHasSize

but newer syncthing versions stamp the fixed SyntheticDirectorySize constant
(128) on every scanned directory, so a receiving node flagged every incoming
directory entry from such a peer as "non-file type with nonzero size" and
mixed-version synchronization of directory entries broke. The fix splits the
case by kind: a directory may carry size 0 or SyntheticDirectorySize; a
symlink stays exactly size 0.

Usage: fix_protocol_consistency.py /app/src/lib/protocol/protocol.go
"""
import sys

BUGGY = """	case f.Type != FileInfoTypeFile && f.Size != 0:
		// Only files should have a size
		return errNonFileHasSize
"""

FIXED = """	case f.IsDirectory() && f.Size != 0 && f.Size != SyntheticDirectorySize:
		// Directories should be size zero or the synthetic directory size
		return errNonFileHasSize

	case f.IsSymlink() && f.Size != 0:
		// Symlinks should be size zero
		return errNonFileHasSize
"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_protocol_consistency.py PATH_TO_PROTOCOL_GO", file=sys.stderr)
        return 2
    path = sys.argv[1]
    src = open(path, encoding="utf-8").read()
    count = src.count(BUGGY)
    if count != 1:
        print(f"error: expected exactly one occurrence of the buggy size check, found {count}", file=sys.stderr)
        return 1
    open(path, "w", encoding="utf-8").write(src.replace(BUGGY, FIXED))
    print(f"patched {path}: directories may carry the synthetic directory size")
    return 0


if __name__ == "__main__":
    sys.exit(main())