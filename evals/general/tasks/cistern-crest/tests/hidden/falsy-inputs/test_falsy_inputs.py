# -*- coding: utf-8 -*-
"""Hidden case 2 for cistern-crest: value- and key-option inputs.

The upstream regression test drives the default key ("date"); these cases
exercise the same run() code path through the 'value' formatter option and a
custom 'key' option, with fields that carry no usable number.
"""

import logging
import sys

sys.path.insert(0, "/app/src")

from gallery_dl.postprocessor.mtime import MtimePP


class _Job:
    def __init__(self):
        self.hooks = {}

    def get_logger(self, name):
        return logging.getLogger("cistern-crest." + name)

    def register_hooks(self, hooks, options=None):
        self.hooks.update(hooks)


class _Pathfmt:
    def __init__(self, kwdict):
        self.kwdict = kwdict


def _run(pp, kwdict):
    pp.run(_Pathfmt(kwdict))
    return kwdict["_mtime_meta"]


def test_value_option_missing_field_is_falsy():
    pp = MtimePP(_Job(), {"value": "{mtime64}"})
    kwdict = {"category": "test", "mtime64": "315532800"}
    assert _run(pp, kwdict) == 315532800

    del kwdict["mtime64"]
    assert not _run(pp, kwdict)


def test_value_option_empty_string_is_falsy():
    pp = MtimePP(_Job(), {"value": "{mtime64}"})
    kwdict = {"category": "test", "mtime64": ""}
    assert not _run(pp, kwdict)


def test_value_option_garbage_number_is_falsy():
    pp = MtimePP(_Job(), {"value": "{mtime64}"})
    kwdict = {"category": "test", "mtime64": "not-a-number"}
    assert not _run(pp, kwdict)


def test_custom_key_missing_is_falsy():
    pp = MtimePP(_Job(), {"key": "published"})
    kwdict = {"category": "test", "published": "315532800"}
    assert _run(pp, kwdict) == 315532800

    kwdict.pop("published")
    assert not _run(pp, kwdict)