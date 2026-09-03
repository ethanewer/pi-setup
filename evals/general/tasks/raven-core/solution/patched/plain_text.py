#!/usr/bin/env python3
"""plain_text: extract the plain text of an XML document.

Remediated: the raw input is pre-scanned by a DTD policy check that rejects
external entity declarations and any entity reference chain deeper than the
documented maximum expansion depth before the SAX driver ever sees it.
Benign documents still extract exactly as before.
"""
import re
import sys

import xml.sax
from xml.sax.handler import ContentHandler

MAX_ENTITY_DEPTH = 6


class UnsafeDocument(Exception):
    pass


def doctype_end(src, i):
    n = len(src)
    quote = None
    depth = 0
    while i < n:
        c = src[i]
        if quote:
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
        elif c == ">" and depth <= 0:
            return i
        i += 1
    return n


def vet(text):
    match = re.search(r"<![ \t\r\n]*DOCTYPE\b", text, re.I)
    if not match:
        return
    end = doctype_end(text, match.end())
    region = text[match.start():end + 1]

    declarations = {}
    entity_re = re.compile(
        r"<![ \t\r\n]*ENTITY[ \t\r\n]+([A-Za-z_:][\w:.-]*)"
        r"(?:[ \t\r\n]+(SYSTEM|PUBLIC))?"
        r"[ \t\r\n]*([\"'])(.*?)\3\s*>",
        re.S,
    )
    for decl in entity_re.finditer(region):
        name = decl.group(1)
        if decl.group(2) is not None:
            raise UnsafeDocument("external entity declared: " + name)
        declarations[name] = decl.group(4)

    memo = {}

    def depth(name, active):
        if name in memo:
            return memo[name]
        if name in active:
            raise UnsafeDocument("cyclic entity chain: " + name)
        body = declarations.get(name)
        if body is None:
            return 1
        refs = set(re.findall(r"&([A-Za-z_:][\w:.-]*);", body))
        refs = {r for r in refs if r in declarations}
        if not refs:
            memo[name] = 1
            return 1
        active.add(name)
        deepest = 0
        for ref in refs:
            deepest = max(deepest, depth(ref, active))
        active.discard(name)
        memo[name] = deepest + 1
        return memo[name]

    for name in declarations:
        if depth(name, set()) > MAX_ENTITY_DEPTH:
            raise UnsafeDocument(
                "entity chain exceeds documented depth (%d): %s"
                % (MAX_ENTITY_DEPTH, name)
            )


class TextCollector(ContentHandler):
    def __init__(self):
        self._parts = []

    def characters(self, content):
        self._parts.append(content)


def main(argv):
    if len(argv) < 2:
        print("usage: plain_text.py <input.xml>", file=sys.stderr)
        return 2
    with open(argv[1], "r", encoding="utf-8") as handle:
        raw = handle.read()
    vet(raw)
    parser = xml.sax.make_parser()
    collector = TextCollector()
    parser.setContentHandler(collector)
    parser.parse(argv[1])
    sys.stdout.write("OK " + "".join(collector._parts))
    return 0


def _entry():
    try:
        return main(sys.argv)
    except UnsafeDocument as exc:
        print("plain_text: rejected: %s" % exc, file=sys.stderr)
        return 1
    except Exception as exc:
        print("plain_text: rejected: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(_entry())