#!/usr/bin/env python3
"""Apply the upstream fix for the root_path mojibake to a falcon checkout.

The bug (falconry/falcon #2667): Request.root_path returns the WSGI
SCRIPT_NAME environ value verbatim, skipping the PEP 3333 latin-1 tunnel
decoding that PATH_INFO gets, so a non-ASCII mount prefix is reported as
mojibake. The fix decodes a non-ASCII SCRIPT_NAME from iso-8859-1 to UTF-8
(with replacement for malformed sequences), mirroring the PATH_INFO handling.

Usage: fix_request.py <path-to-falcon/request.py>
"""
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    src = f.read()

old = (
    "            # TODO(0xMattB): Implement advanced typing to type as 'str' (see PR #2599)\n"
    "            return self.env['SCRIPT_NAME']  # type: ignore[no-any-return]\n"
)
new = (
    "            root_path: str = self.env['SCRIPT_NAME']\n"
    "            if not root_path.isascii():\n"
    "                root_path = root_path.encode('iso-8859-1').decode('utf-8', 'replace')\n"
    "            return root_path\n"
)

if old not in src:
    raise SystemExit('fix target not found in %s (already patched?)' % path)

with open(path, 'w', encoding='utf-8') as f:
    f.write(src.replace(old, new, 1))

print('patched %s' % path)