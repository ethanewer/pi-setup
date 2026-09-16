#!/usr/bin/env python3
"""Apply the upstream gin fix for the case-insensitive fixed-path lookup.

The bug (upstream issue #4535): findCaseInsensitivePathRec, when walking a
node that has BOTH static children and a wildcard (param or catch-all) child,
picked n.children[0] blindly and switched on its type.  addChild keeps the
wildcard child LAST in the children array, so children[0] of such a node is a
plain static child, which hits the "default" arm and panics with
"invalid node type", killing the whole server process.  The upstream fix
first scans the node's static children through its byte indices (matching
exact, lowercased and uppercased first rune, recursively) and only falls back
to the wildcard child - the LAST element of children - when no static child
matches, exactly like getValue() does.

Idempotent; exits non-zero if the expected anchor is not found exactly once.
"""

import sys
from pathlib import Path

OLD = "\t\tn = n.children[0]\n\t\tswitch n.nType {\n"
NEW = (
    "\t\t// When wildChild is true, try static children first (via indices)\n\t\t// before falling back to the wildcard child. This ensures that\n\t\t// case-insensitive lookups prefer static routes over param routes\n\t\t// (e.g., /PREFIX/XXX should resolve to /prefix/xxx, not match :id).\n\t\tif len(n.indices) > 0 {\n\t\t\trb = shiftNRuneBytes(rb, npLen)\n\n\t\t\tif rb[0] != 0 {\n\t\t\t\tidxc := rb[0]\n\t\t\t\tfor i, c := range []byte(n.indices) {\n\t\t\t\t\tif c == idxc {\n\t\t\t\t\t\tif out := n.children[i].findCaseInsensitivePathRec(\n\t\t\t\t\t\t\tpath, ciPath, rb, fixTrailingSlash,\n\t\t\t\t\t\t); out != nil {\n\t\t\t\t\t\t\treturn out\n\t\t\t\t\t\t}\n\t\t\t\t\t\tbreak\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t} else {\n\t\t\t\tvar rv rune\n\t\t\t\tvar off int\n\t\t\t\tfor max_ := min(npLen, 3); off < max_; off++ {\n\t\t\t\t\tif i := npLen - off; utf8.RuneStart(oldPath[i]) {\n\t\t\t\t\t\trv, _ = utf8.DecodeRuneInString(oldPath[i:])\n\t\t\t\t\t\tbreak\n\t\t\t\t\t}\n\t\t\t\t}\n\n\t\t\t\tlo := unicode.ToLower(rv)\n\t\t\t\tutf8.EncodeRune(rb[:], lo)\n\t\t\t\trb = shiftNRuneBytes(rb, off)\n\n\t\t\t\tidxc := rb[0]\n\t\t\t\tfor i, c := range []byte(n.indices) {\n\t\t\t\t\tif c == idxc {\n\t\t\t\t\t\tif out := n.children[i].findCaseInsensitivePathRec(\n\t\t\t\t\t\t\tpath, ciPath, rb, fixTrailingSlash,\n\t\t\t\t\t\t); out != nil {\n\t\t\t\t\t\t\treturn out\n\t\t\t\t\t\t}\n\t\t\t\t\t\tbreak\n\t\t\t\t\t}\n\t\t\t\t}\n\n\t\t\t\tif up := unicode.ToUpper(rv); up != lo {\n\t\t\t\t\tutf8.EncodeRune(rb[:], up)\n\t\t\t\t\trb = shiftNRuneBytes(rb, off)\n\n\t\t\t\t\tidxc := rb[0]\n\t\t\t\t\tfor i, c := range []byte(n.indices) {\n\t\t\t\t\t\tif c == idxc {\n\t\t\t\t\t\t\tif out := n.children[i].findCaseInsensitivePathRec(\n\t\t\t\t\t\t\t\tpath, ciPath, rb, fixTrailingSlash,\n\t\t\t\t\t\t\t); out != nil {\n\t\t\t\t\t\t\t\treturn out\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\tbreak\n\t\t\t\t\t\t}\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\n\t\t// Fall back to wildcard child, which is always at the end of the array\n\t\tn = n.children[len(n.children)-1]\n\t\tswitch n.nType {\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_tree.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if src.count(OLD) == 0 and NEW in src:
        print("tree.go already carries the static-first lookup")
        return 0
    if src.count(OLD) != 1:
        print(f"FATAL: expected anchor found {src.count(OLD)} times, not exactly once:",
              file=sys.stderr)
        return 1

    path.write_text(src.replace(OLD, NEW, 1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
