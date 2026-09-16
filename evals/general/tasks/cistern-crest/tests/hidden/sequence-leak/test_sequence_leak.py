# -*- coding: utf-8 -*-
"""Hidden case 1 for cistern-crest: the several-files-one-job scenario.

One download job processes several files; the metadata dict is shared across
them.  A file whose metadata has no usable date must not be stamped with a
previous file's modification time, and the 'no date' sentinel must not
translate into an absurd (year 0001) timestamp.
"""

import logging
import sys

sys.path.insert(0, "/app/src")

from datetime import datetime

from gallery_dl import dt
from gallery_dl.postprocessor.mtime import MtimePP


class _Job:
    """Minimal stand-in: MtimePP needs get_logger() and register_hooks()."""

    def __init__(self):
        self.hooks = {}

    def get_logger(self, name):
        return logging.getLogger("cistern-crest." + name)

    def register_hooks(self, hooks, options=None):
        self.hooks.update(hooks)


class _Pathfmt:
    """PathFormat stand-in: MtimePP.run() only touches .kwdict."""

    def __init__(self, kwdict):
        self.kwdict = kwdict


def _run(pp, kwdict):
    pp.run(_Pathfmt(kwdict))
    return kwdict["_mtime_meta"]


def _pp(**options):
    return MtimePP(_Job(), options)


def test_second_file_without_date_keeps_no_stale_mtime():
    pp = _pp()
    kwdict = {"category": "test", "filename": "a", "extension": "ext"}

    kwdict["date"] = datetime(1980, 1, 1)          # first file
    assert _run(pp, kwdict) == 315532800

    del kwdict["date"]                             # second file: no date at all
    assert not _run(pp, kwdict)

    kwdict["date"] = datetime(2000, 2, 29)         # third file: fresh date again
    assert _run(pp, kwdict) == 951782400


def test_explicit_none_date_clears_previous_mtime():
    pp = _pp()
    kwdict = {"category": "test"}

    kwdict["date"] = datetime(1984, 2, 29)
    assert _run(pp, kwdict) == 446860800

    kwdict["date"] = None
    assert not _run(pp, kwdict)


def test_null_datetime_sentinel_produces_no_absurd_timestamp():
    pp = _pp()
    kwdict = {"category": "test", "date": datetime(1980, 1, 1)}
    assert _run(pp, kwdict) == 315532800

    kwdict["date"] = dt.NONE
    value = _run(pp, kwdict)
    assert not value