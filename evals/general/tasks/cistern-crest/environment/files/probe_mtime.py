#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Reproduce the --mtime metadata handling bug in the /app/src gallery-dl checkout.

One download job writes several files.  The mtime postprocessor reads each
file's date metadata and records the resulting Unix timestamp in the shared
metadata dict as "_mtime_meta", which the downloader then applies to the file.

Expected behaviour: a file whose metadata carries no usable date must not be
stamped with any timestamp (in particular not with a previous file's).
"""

from datetime import datetime

from gallery_dl import dt
from gallery_dl.postprocessor.mtime import MtimePP


class _Job:
    """Minimal job stand-in: MtimePP only needs the logger and the hook table."""

    def __init__(self):
        self.hooks = {}

    def get_logger(self, name):
        import logging
        return logging.getLogger("cistern-crest.probe." + name)

    def register_hooks(self, hooks, options=None):
        self.hooks.update(hooks)


class _Pathfmt:
    """PathFormat stand-in: MtimePP.run() only reads .kwdict."""

    def __init__(self, kwdict):
        self.kwdict = kwdict


def main():
    pp = MtimePP(_Job(), {})          # defaults: key="date", event=("file",)
    kwdict = {"category": "test", "filename": "sample", "extension": "jpg"}
    path = _Pathfmt(kwdict)

    kwdict["date"] = datetime(1980, 1, 1)   # first file: valid date
    pp.run(path)
    print("first file  _mtime_meta:", kwdict["_mtime_meta"])

    del kwdict["date"]                      # second file: no date metadata at all
    pp.run(path)
    print("second file _mtime_meta:", kwdict["_mtime_meta"])

    kwdict["date"] = dt.NONE                # third file: invalid parsed date sentinel
    pp.run(path)
    print("invalid date _mtime_meta:", kwdict["_mtime_meta"])


if __name__ == "__main__":
    main()