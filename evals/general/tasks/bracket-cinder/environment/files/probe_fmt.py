#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Probe for bracket-cinder.

Formats the same kind of template strings the gallery-dl keyword-evaluation
code path does (formatter.parse(value, None, util.identity)), to show which
value shapes crash and which work. A working fix must make every template
below format without raising.
"""

import datetime
import os
import sys

sys.path.insert(0, os.environ.get("GDL_SRC", "/app/src"))

from gallery_dl import formatter, util  # noqa: E402

TEMPLATES = [
    # (label, template, kwdict, fmt)
    ("single int placeholder           ",
     "{t}", {"t": 1262304000}, util.identity),
    ("single datetime placeholder      ",
     "{dt}", {"dt": datetime.datetime(2010, 1, 1)}, util.identity),
    ("single placeholder + int fmt     ",
     "{t}", {"t": 1262304000}, int),
    ("text + int placeholder           ",
     "https://cdn.example.com/a/{id}/b", {"id": 1262304000}, util.identity),
    ("text + datetime placeholder      ",
     "posted on {dt}", {"dt": datetime.datetime(2010, 1, 1)}, util.identity),
    ("text + None placeholder          ",
     "gallery {name} {mtime}", {"name": "x", "mtime": None}, util.identity),
    ("text + int placeholder + int fmt ",
     "foo {t}", {"t": 1262304000}, int),
]

failures = 0
for label, template, kwdict, fmt in TEMPLATES:
    try:
        value = formatter.parse(template, None, fmt).format_map(kwdict)
    except Exception as exc:
        failures += 1
        print("FAIL  %s : %s: %s" % (label, template, exc))
    else:
        print("ok    %s : %s -> %r" % (label, template, value))

if failures:
    print("\n%d of %d template shapes raised an exception" %
          (failures, len(TEMPLATES)))
    sys.exit(1)
print("\nall %d template shapes formatted successfully" % len(TEMPLATES))