#!/usr/bin/env python3
"""plain_text: extract the plain text of an XML document.

No special entity handling is configured: the SAX driver ignores external
general entities by default (nothing is fetched), while internal entity
expansion still follows whatever the document declares in its own DTD subset.
"""
import sys

import xml.sax
from xml.sax.handler import ContentHandler


class TextCollector(ContentHandler):
    def __init__(self):
        self._parts = []

    def characters(self, content):
        self._parts.append(content)


def main(argv):
    if len(argv) < 2:
        print("usage: plain_text.py <input.xml>", file=sys.stderr)
        return 2
    parser = xml.sax.make_parser()
    collector = TextCollector()
    parser.setContentHandler(collector)
    parser.parse(argv[1])
    sys.stdout.write("OK " + "".join(collector._parts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
