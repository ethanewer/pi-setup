"""shadow-var rule plugin.

Flags a name binding that is bound in an inner scope while the same name is
already bound in an outer (ancestor) scope, per the documented block model:

  * module forms the root scope;
  * every compound statement (if / elif / else / for / while / def)
    introduces a child scope holding its suite;
  * a name is bound in the scope that directly contains its binding statement;

Bindings come from assignment targets, for-loop targets, function parameters
and function-definition names.  A binding is a *shadow* when its name is
already bound in any strict ancestor scope.  Re-defining the same name within
one scope is not a shadow.
"""


class ShadowVar(object):
    id = "shadow-var"
    description = "flags a binding in an inner scope that shadows an outer binding"

    def check(self, node, ctx):
        if node.type != "Module":
            return []
        out = []
        self._visit(ctx.root.scope_tree, out)
        return out

    def _visit(self, scope, out):
        ancestors = []
        s = scope.parent
        while s is not None:
            ancestors.append(s)
            s = s.parent
        for (name, bnode, kind) in scope.bindings:
            for anc in ancestors:
                if name in anc.names:
                    if bnode.type == "FunctionDef":
                        line = bnode.name_line
                        col = bnode.name_col
                    else:
                        line = bnode.line
                        col = bnode.col
                    out.append({
                        "id": self.id,
                        "line": line,
                        "col": col,
                        "message": "shadowing of %s" % name,
                    })
                    break
        for child in scope.children:
            self._visit(child, out)