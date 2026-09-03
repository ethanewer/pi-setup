#!/usr/bin/env python3
"""directive_loader: an entity-directive reader.

Parses the document with xml.dom.minidom and expands `&name;` references by
applying the substitution directives read from the document's DTD internal
subset (the DOCTYPE's declared entities). External entity references are not
fetched: xml.dom.expabuilder skips them, so only the document's own internal
substitutions are in play.
"""
import sys

import xml.dom.minidom


def collect(node, out):
    for child in node.childNodes:
        if child.nodeType in (
            xml.dom.minidom.Node.TEXT_NODE,
            xml.dom.minidom.Node.CDATA_SECTION_NODE,
        ):
            out.append(child.data)
        elif child.nodeType == xml.dom.minidom.Node.ELEMENT_NODE:
            collect(child, out)


def main(argv):
    if len(argv) < 2:
        print("usage: directive_loader.py <input.xml>", file=sys.stderr)
        return 2
    doc = xml.dom.minidom.parse(argv[1])
    pieces = []
    collect(doc.documentElement, pieces)
    sys.stdout.write("OK " + "".join(pieces))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
