#!/usr/bin/env python3
"""Apply the case-exact attribute-removal fix to DOMPurify's src/purify.ts.

The defect: for an HTML element in an HTML document, name-based
removeAttribute(name)/getAttributeNode(name) ASCII-lowercase the *lookup key*
but never the stored qualified name. An attribute created with a
case-preserving API (setAttributeNS, createAttributeNS, or imported from an
XML/XHTML document) therefore keeps e.g. `ONERROR`; the sanitizer lowercases
the name for its policy decision and correctly rejects it, but the removal
looks up `onerror`, finds nothing, and the attribute survives the walk.
Fixing it means removing the exact Attr node (removeAttributeNode), which is
case- and namespace-exact, and falling back to name-based removal when the
caller could not supply the node.

Idempotent: exits 0 when the fixed `_removeAttribute` is already present.
Fails loudly if the expected parent-commit snippets are not found.
"""

import sys


OLD_FN_START = """  const _removeAttribute = function (name: string, element: Element): void {
    try {
      arrayPush(DOMPurify.removed, {
        attribute: element.getAttributeNode(name),
        from: element,
      });
    } catch (_) {
      arrayPush(DOMPurify.removed, {
        attribute: null,
        from: element,
      });
    }

    element.removeAttribute(name);
"""

NEW_FN_START = """  const _removeAttribute = function (
    name: string,
    element: Element,
    attr?: Attr | null
  ): void {
    if (!attr) {
      try {
        attr = element.getAttributeNode(name);
      } catch (_) {
        attr = null;
      }
    }

    arrayPush(DOMPurify.removed, {
      attribute: attr || null,
      from: element,
    });

    try {
      if (attr) {
        element.removeAttributeNode(attr);
      } else {
        element.removeAttribute(name);
      }
    } catch (_) {
      /* Clobbered or already-detached node - best-effort fall back to a
         name-based removal so the "is" handling below still runs. */
      try {
        element.removeAttribute(name);
      } catch (_) {}
    }
"""

# All six call sites inside the attribute walk share the same mechanical shape:
# `_removeAttribute(name, currentNode);` -> `_removeAttribute(name, currentNode, attr);`
OLD_CALL = "        _removeAttribute(name, currentNode);\n"
NEW_CALL = "        _removeAttribute(name, currentNode, attr);\n"

EXPECTED_CALL_SITES = 6


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_purify.py PATH/TO/src/purify.ts", file=sys.stderr)
        return 2
    target = sys.argv[1]
    src = open(target, encoding="utf-8").read()

    if "element.removeAttributeNode(attr);" in src:
        print("src/purify.ts already carries the case-exact removal fix")
        return 0

    if OLD_FN_START not in src:
        print("ERROR: parent-commit _removeAttribute body not found; aborting",
              file=sys.stderr)
        return 1

    n_sites = src.count(OLD_CALL)
    if n_sites < EXPECTED_CALL_SITES:
        print(f"ERROR: expected at least {EXPECTED_CALL_SITES} name-based call "
              f"sites, found {n_sites}", file=sys.stderr)
        return 1

    src = src.replace(OLD_FN_START, NEW_FN_START, 1)
    src = src.replace(OLD_CALL, NEW_CALL)

    if "element.removeAttributeNode(attr);" not in src:
        print("ERROR: fix not applied; aborting", file=sys.stderr)
        return 1

    open(target, "w", encoding="utf-8").write(src)
    print("src/purify.ts patched: case-exact removeAttributeNode removal")
    return 0


if __name__ == "__main__":
    sys.exit(main())