#!/usr/bin/env python3
"""snippet_extract: pull plain text out of an XML document.

Builds on the xml.sax driver and enables external-entity processing through a
passthrough entity resolver: any external general entity the document asks
for is handed back to the parser by its system identifier, so a SYSTEM entity
whose system id points at a local `file://` resource is read and spliced
straight into the extracted text.
"""
import sys

import xml.sax
from xml.sax.handler import ContentHandler, feature_external_ges
from xml.sax.xmlreader import InputSource


class TextCollector(ContentHandler):
    def __init__(self):
        self._parts = []

    def characters(self, content):
        self._parts.append(content)


class PassthroughResolver:
    """Resolves external entities by handing their system id back to SAX."""

    def resolveEntity(self, public_id, system_id):
        if system_id:
            source = InputSource(system_id)
            source.setPublicId(public_id)
            return source
        return None


def main(argv):
    if len(argv) < 2:
        print("usage: snippet_extract.py <input.xml>", file=sys.stderr)
        return 2
    parser = xml.sax.make_parser()
    parser.setFeature(feature_external_ges, True)
    collector = TextCollector()
    parser.setContentHandler(collector)
    parser.setEntityResolver(PassthroughResolver())
    parser.parse(argv[1])
    sys.stdout.write("OK " + "".join(collector._parts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
