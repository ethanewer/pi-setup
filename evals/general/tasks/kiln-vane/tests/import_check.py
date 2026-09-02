#!/usr/bin/env python3
"""Import-check helper: loads /app/loom.py as a module, calls weave() on the
tile in the given JSON, and compares to the expected grid JSON."""
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("loom", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
with open(sys.argv[2]) as fh:
    tile = json.load(fh)["tile"]
with open(sys.argv[3]) as fh:
    want = json.load(fh)
got = mod.weave(tile)
ok = got == want
print("weave MATCH" if ok else "weave MISMATCH")
sys.exit(0 if ok else 1)
