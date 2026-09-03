"""forbid-call rule plugin.

Flags calls whose callee name (the final identifier of a direct or attribute
form) is listed in the configured forbidden set, but only when the call
appears inside a function body (at any depth).  Calls at module top level are
never reported, and calls written in a function's parameter defaults are at
the enclosing depth.

The forbidden set is read from ``<rules_dir>/forbid_call.json`` (a JSON array
of names).  The anchor of a finding is the text position of the callee name
token.
"""

import json
import os

_MUTABLE = None


class ForbidCall(object):
    id = "forbid-call"
    description = "flags calls (direct and attribute forms) to configured " \
                  "names when they occur inside function bodies"

    def __init__(self):
        self._forbidden = None

    def _load(self, ctx):
        if self._forbidden is None:
            path = os.path.join(ctx.rules_dir, "forbid_call.json")
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    self._forbidden = set(json.load(fh))
            except Exception:
                self._forbidden = set()
        return self._forbidden

    def check(self, node, ctx):
        if node.type != "Call":
            return []
        if node.name not in self._load(ctx):
            return []
        if getattr(node, "func_depth", 0) < 1:
            return []
        return [{
            "id": self.id,
            "line": node.name_line,
            "col": node.name_col,
            "message": "forbidden call to %s" % node.name,
        }]