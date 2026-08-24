#!/usr/bin/env python3
"""Deterministic regex-rule engine for the item-064 data pipeline.

Engine.py is FIXED. Do not modify it. All classification behaviour is
expressed purely through the data in /app/rules.json (the "no-code" mechanism).
"""

import re


def _flags(flags):
    f = 0
    for name in (flags or []):
        f |= getattr(re, name.upper(), 0)
    return f


def substitute(text, rules):
    """Apply every substitution rule in order. Later rules operate on the
    text rewritten by earlier rules, so a normalizing chain is possible."""
    for r in rules:
        fl = _flags(r.get("flags"))
        if re.search(r["pattern"], text, fl):
            text = re.sub(r["pattern"], r["replace"], text, fl)
    return text


def classify(text, rules):
    """Return {"kind", "verdict"} for `text`.

    LAST-MATCH SEMANTICS: rules are evaluated in list order and each matching
    rule overwrites the previous result. The rule closest to the end of the
    list that matches the whole string determines the final (kind, verdict).
    """
    res = {"kind": "none", "verdict": "none"}
    for r in rules:
        fl = _flags(r.get("flags"))
        if re.compile(r["pattern"], fl).fullmatch(text):
            res = {
                "kind": r.get("kind", "none"),
                "verdict": r.get("verdict", "none"),
            }
    return res