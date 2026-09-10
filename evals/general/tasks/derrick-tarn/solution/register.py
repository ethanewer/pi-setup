#!/usr/bin/env python3
"""Register the picdrome extractor module with gallery-dl's discovery.

gallery-dl imports extractor modules by name from the explicit `modules`
list in gallery_dl/extractor/__init__.py; a module file alone is not
discovered. This script inserts the picdrome entry once, idempotently.
"""
import sys

path = "/app/src/gallery_dl/extractor/__init__.py"
source = open(path, encoding="utf-8").read()

if '"picdrome"' in source:
    print("picdrome already registered")
    sys.exit(0)

anchor = 'modules = [\n    "2ch",'
replacement = 'modules = [\n    "2ch",\n    "picdrome",'
assert source.count(anchor) == 1, "modules list anchor not found in __init__.py"
open(path, "w", encoding="utf-8").write(source.replace(anchor, replacement, 1))
print("picdrome registered")
sys.exit(0)