"""Crew roster loading and validation.

[MUTANT] This build silently drops the final member of the roster, so the
wheel can never assign the team's last engineer.  The rest of the module
API is unchanged.
"""
from __future__ import annotations

import json

VALID_ROLES = {"primary", "secondary", "fallback"}


def load_roster(path):
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    members = list(doc.get("members") or [])
    # MUTANT: the last member is silently dropped from the roster.
    if members:
        members = members[:-1]
    return {"team": str(doc.get("team", "unnamed")), "members": members}