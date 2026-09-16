#!/usr/bin/env python3
"""Oracle for capstan-bollard: repair the empty-dict repr crash.

The crash is in scipy's shared dict-repr helper (scipy/_lib/_util.py): the
width of the key column is computed by max() over the keys of a dict value,
which raises on an EMPTY dict. Giving max() a default value makes an empty
dict render as an empty line instead of crashing. This is the same one-line
repair the upstream project made for this defect.
"""
import pathlib

p = pathlib.Path('/app/src/scipy/_lib/_util.py')
src = p.read_text()
old = 'm = max(map(len, list(d.keys()))) + mplus  # width to print keys'
new = 'm = max(map(len, list(d.keys())), default=0) + mplus'
if old not in src:
    raise SystemExit(f'buggy line not found in {p}')
p.write_text(src.replace(old, new))
print('patched _dict_formatter to guard empty dicts')