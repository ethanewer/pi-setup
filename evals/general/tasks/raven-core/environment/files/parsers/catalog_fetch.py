#!/usr/bin/env python3
"""catalog_fetch: flatten an XML catalog down to its text content.

Uses xml.sax with external-entity processing switched on and an entity
resolver that transitively resolves a `file://` system identifier by opening
the resource it names, so the bytes of a referenced local file can be pulled
into the flattened text.
"""
import sys

import xml.sax
from xml.sax.handler import ContentHandler, feature_external_ges
from xml.sax.xmlreader import InputSource


class Flatten(ContentHandler):
    def __init__(self):
        self.chunks = []

    def characters(self, content):
        self.chunks.append(content)


class LocalFileResolver:
    """Resolves `file://` system ids by opening the named local resource."""

    def resolveEntity(self, public_id, system_id):
        if not system_id:
            return None
        if system_id.startswith("file://"):
            source = InputSource(system_id)
            source.setPublicId(public_id)
            # Let the SAX driver open the resource from its system id.
            return source
        return None


def main(argv):
    if len(argv) < 2:
        print("usage: catalog_fetch.py <input.xml>", file=sys.stderr)
        return 2
    parser = xml.sax.make_parser()
    parser.setFeature(feature_external_ges, True)
    handler = Flatten()
    parser.setContentHandler(handler)
    parser.setEntityResolver(LocalFileResolver())
    parser.parse(argv[1])
    sys.stdout.write("OK " + "".join(handler.chunks))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
