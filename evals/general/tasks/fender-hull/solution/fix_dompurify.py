#!/usr/bin/env python3
"""Apply the minimal upstream-equivalent fix for fender-hull to src/purify.ts.

The bug (DOMpurify issue #1560): in-place sanitize of a live subtree reads the
traversal root's owning document through a DIRECT property read on the root
element. HTMLFormElement has [LegacyOverrideBuiltIns]; a child (or an own
accessor leftover in the caller's page) that shadows the document-owner
property makes that direct read return an arbitrary element, and
createNodeIterator.call(<that element>, ...) throws before the walk's
fail-closed barrier runs. The caller then gets control back with event-handler
attributes still attached to the surviving live subtree.

The fix makes the document-owner read clobber-immune by going through the
cached Node.prototype getter (own/child property shadowing cannot touch a
prototype accessor), applies the same read in the SAFE_FOR_TEMPLATES scrub,
and moves iterator construction inside the fail-closed exception barrier so
even a failing iterator cannot skip the neutralize pass.

Only the ownerDocument part of the upstream change is applied here; the
hook-allowlist sub-fix that travelled in the same upstream commit is out of
scope for this task (it is not observable in this reproduction) and is not
required for the test suite.

Usage: fix_dompurify.py /path/to/src/purify.ts
Every replacement must match exactly once or the script fails loudly.
"""

import sys

ANCHORS = [
    (
        "const getNodeName =\n"
        "    Node && Node.prototype ? lookupGetter(Node.prototype, 'nodeName') : null;\n",
        "const getNodeName =\n"
        "    Node && Node.prototype ? lookupGetter(Node.prototype, 'nodeName') : null;\n"
        "  const getOwnerDocument =\n"
        "    Node && Node.prototype\n"
        "      ? lookupGetter(Node.prototype, 'ownerDocument')\n"
        "      : null;\n",
    ),
    (
        "  const _createNodeIterator = function (root: Node): NodeIterator {\n"
        "    return createNodeIterator.call(\n"
        "      root.ownerDocument || root,\n",
        "  const _createNodeIterator = function (root: Node): NodeIterator {\n"
        "    /* Read ownerDocument through the cached Node.prototype getter, never the\n"
        "       direct property: HTMLFormElement has [LegacyOverrideBuiltIns], so a\n"
        "       clobbering child or own accessor shadows the prototype getter and a\n"
        "       direct read returns that element instead of the real Document, and\n"
        "       createNodeIterator.call(<that element>, ...) throws before the\n"
        "       fail-closed barrier. The cached getter returns the real Document\n"
        "       regardless of the clobber. */\n"
        "    const doc = getOwnerDocument ? getOwnerDocument(root) : root.ownerDocument;\n"
        "    return createNodeIterator.call(\n"
        "      doc || root,\n",
    ),
    (
        "  const _scrubTemplateExpressions = function (node: Element): void {\n"
        "    node.normalize();\n"
        "    const walker = createNodeIterator.call(\n"
        "      node.ownerDocument || node,\n",
        "  const _scrubTemplateExpressions = function (node: Element): void {\n"
        "    node.normalize();\n"
        "    /* Clobber-safe ownerDocument read, same reasoning as _createNodeIterator:\n"
        "       under SAFE_FOR_TEMPLATES this runs on the live IN_PLACE root, which may\n"
        "       carry an override of the document-owner property. */\n"
        "    const doc = getOwnerDocument ? getOwnerDocument(node) : node.ownerDocument;\n"
        "    const walker = createNodeIterator.call(\n"
        "      doc || node,\n",
    ),
    (
        "    const walkRoot: Node = inPlace ? (dirty as Node) : body;\n"
        "    const nodeIterator = _createNodeIterator(walkRoot);\n\n"
        "    /* Now start iterating over the created document.\n",
        "    const walkRoot: Node = inPlace ? (dirty as Node) : body;\n\n"
        "    /* Now start iterating over the created document.\n",
    ),
    (
        "    try {\n"
        "      while ((currentNode = nodeIterator.nextNode())) {\n",
        "    try {\n"
        "      const nodeIterator = _createNodeIterator(walkRoot);\n"
        "      while ((currentNode = nodeIterator.nextNode())) {\n",
    ),
]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_dompurify.py <src/purify.ts>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()

    for old, new in ANCHORS:
        n = src.count(old)
        if n != 1:
            print(
                f"anchor matched {n} times (want 1): {old.splitlines()[0]!r}",
                file=sys.stderr,
            )
            return 1
        src = src.replace(old, new)

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)
    print("patched OK: getOwnerDocument getter + clobber-safe reads + barrier-moved iterator")
    return 0


if __name__ == "__main__":
    sys.exit(main())