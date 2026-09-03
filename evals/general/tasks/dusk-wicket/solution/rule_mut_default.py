"""mut-default rule plugin.

Flags a function parameter whose default value is a mutable literal: a list
(``[...]``), a dict (``{k: v, ...}``) or a set (``{...}``; an empty ``{}``
counts as a mutable dict).  Defaults that are names, calls, numbers, strings,
booleans or None are not flagged.  The anchor is the parameter's name token.
"""


class MutDefault(object):
    id = "mut-default"
    description = "flags mutable literal defaults in function definitions"

    def check(self, node, ctx):
        if node.type != "FunctionDef":
            return []
        out = []
        for p in node.params:
            if p.default is not None and p.default.type in ("List", "Dict", "Set"):
                out.append({
                    "id": self.id,
                    "line": p.line,
                    "col": p.col,
                    "message": "mutable default for %s" % p.name,
                })
        return out