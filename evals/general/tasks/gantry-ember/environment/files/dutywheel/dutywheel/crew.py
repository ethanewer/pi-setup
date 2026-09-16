"""Crew roster loading and validation.

A crew roster is a JSON document::

    {
      "team": "engineering",
      "members": [
        {"id": "ada-lovelace", "name": "Ada Lovelace",
         "role": "primary",
         "windows": [{"start": "2026-05-18T05:00:00Z",
                      "end":   "2026-05-18T12:00:00Z"}]}
      ]
    }

Each member has a stable lowercase-hyphenated ``id``, a display ``name``,
a ``role`` in ``{"primary", "secondary", "fallback"}`` and a (possibly
empty) list of maintenance ``windows`` the member is unavailable during.
Windows are ISO-8601 UTC timestamps; an expired window does not block
anyone.
"""
from __future__ import annotations

import json

VALID_ROLES = {"primary", "secondary", "fallback"}


def load_roster(path):
    """Load and validate a crew roster from a JSON file.

    Raises ValueError when the document is malformed, a member is missing a
    required field, a role is unknown, or member ids are not unique.
    """
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    if not isinstance(doc, dict) or not isinstance(doc.get("members"), list):
        raise ValueError("roster must be an object with a members list")
    members = []
    seen = set()
    for raw in doc["members"]:
        if not isinstance(raw, dict):
            raise ValueError("each member must be an object")
        missing = [k for k in ("id", "name", "role", "windows")
                   if k not in raw]
        if missing:
            raise ValueError("member missing fields: %s" % ", ".join(missing))
        member = {
            "id": str(raw["id"]),
            "name": str(raw["name"]),
            "role": str(raw["role"]),
            "windows": list(raw["windows"]),
        }
        if not member["id"]:
            raise ValueError("member id must not be empty")
        if member["role"] not in VALID_ROLES:
            raise ValueError("unknown role %r" % member["role"])
        if member["id"] in seen:
            raise ValueError("duplicate member id %r" % member["id"])
        seen.add(member["id"])
        members.append(member)
    if not members:
        raise ValueError("roster has no members")
    return {"team": str(doc.get("team", "unnamed")), "members": members}