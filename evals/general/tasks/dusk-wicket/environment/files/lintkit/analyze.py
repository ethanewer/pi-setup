"""Structural analysis helpers layered on the tiny AST.

These are pure *infrastructure*: they annotate the parsed tree so that rule
plugins do not have to re-derive environment facts.  They encode no rule
decision themselves — the decision logic lives entirely in the rule plugins.

Provided:
  * ``all_nodes(node)`` — pre-order walk over the whole tree (yields every
    node, root first).
  * ``build_context(root)`` — annotates each ``Call`` node with
    ``func_depth`` (the number of enclosing ``def`` bodies it sits in), builds
    the documented scope tree at ``root.scope_tree`` and annotates every
    binding node with ``_scope`` and ``_kind``.
"""

import ast_nodes as N


def _expr_children(node):
    """Expression subnodes of an expression/leaf node."""
    t = node.type
    if t == "Call":
        out = [node.func] + list(node.args)
    elif t == "Attribute":
        out = [node.value]
    elif t == "BinOp":
        out = [node.left, node.right]
    elif t == "BoolOp":
        out = list(node.values)
    elif t == "Compare":
        out = [node.left] + list(node.comparators)
    elif t == "UnaryOp":
        out = [node.operand]
    elif t == "List":
        out = list(node.elts)
    elif t == "Dict":
        out = list(node.keys) + list(node.values)
    elif t == "Set":
        out = list(node.elts)
    else:
        out = []
    return [c for c in out if c is not None]


def all_nodes(node):
    yield node
    if node.type in ("Module", "If", "While", "For", "FunctionDef"):
        # handled via stmt children below for correctness of everything
        pass
    for child in _children(node):
        for sub in all_nodes(child):
            yield sub


def _children(node):
    t = node.type
    if t == "Module":
        return node.body
    if t == "FunctionDef":
        defaults = [p.default for p in node.params if p.default is not None]
        return defaults + list(node.body)
    if t in ("Assign", "AugAssign"):
        return [node.value]
    if t == "For":
        return [node.iter] + list(node.body)
    if t == "While":
        return [node.test] + list(node.body)
    if t == "If":
        out = [node.test] + list(node.body)
        for _, b in node.elifs:
            out.append(b)
        out.extend(node.orelse)
        return out
    if t == "Return":
        return [node.value] if node.value is not None else []
    if t == "ExprStmt":
        return [node.value]
    return []


class Scope(object):
    def __init__(self, parent, kind):
        self.parent = parent
        self.kind = kind
        self.children = []
        self.bindings = []  # list of (name, node, kind)
        self.names = set()

    def new_child(self, kind="block"):
        child = Scope(self, kind)
        self.children.append(child)
        return child

    def bind(self, name, node, kind):
        self.bindings.append((name, node, kind))
        self.names.add(name)
        node._scope = self
        node._kind = kind


def _create_binding(scope, name, node, kind):
    scope.bind(name, node, kind)


def _is_statement(node):
    return node.type in (
        "FunctionDef", "Assign", "AugAssign", "For", "While", "If",
        "Return", "Pass", "Break", "Continue", "ExprStmt")


def _build_scopes(stmts, scope, depth):
    for stmt in stmts:
        t = stmt.type
        if t in ("Assign", "AugAssign"):
            scope.bind(stmt.target.id, stmt.target, "assign")
        elif t == "For":
            scope.bind(stmt.target.id, stmt.target, "for")
            body_scope = scope.new_child()
            _build_scopes(stmt.body, body_scope, depth)
        elif t == "While":
            child = scope.new_child()
            _build_scopes(stmt.body, child, depth)
        elif t == "If":
            child = scope.new_child()
            _build_scopes(stmt.body, child, depth)
            for _, ebody in stmt.elifs:
                ech = scope.new_child()
                _build_scopes(ebody, ech, depth)
            och = scope.new_child()
            _build_scopes(stmt.orelse, och, depth)
        elif t == "FunctionDef":
            scope.bind(stmt.name, stmt, "def")
            func_scope = scope.new_child("function")
            for p in stmt.params:
                func_scope.bind(p.name, p, "param")
            _build_scopes(stmt.body, func_scope, depth + 1)
        # Return/Pass/Break/Continue/ExprStmt: no bindings


def _annotate_calls_expr(node, depth):
    t = node.type
    if t == "Call":
        node.func_depth = depth
    for child in _expr_children(node):
        _annotate_calls_expr(child, depth)


def _annotate_calls_stmt(stmt, depth):
    t = stmt.type
    if t in ("Assign", "AugAssign"):
        _annotate_calls_expr(stmt.value, depth)
    elif t == "For":
        _annotate_calls_expr(stmt.iter, depth)
        for s in stmt.body:
            _annotate_calls_stmt(s, depth)
    elif t == "While":
        _annotate_calls_expr(stmt.test, depth)
        for s in stmt.body:
            _annotate_calls_stmt(s, depth)
    elif t == "If":
        _annotate_calls_expr(stmt.test, depth)
        for s in stmt.body:
            _annotate_calls_stmt(s, depth)
        for _, eb in stmt.elifs:
            _annotate_calls_expr(eb[0], depth)
            for s in eb[1]:
                _annotate_calls_stmt(s, depth)
        for s in stmt.orelse:
            _annotate_calls_stmt(s, depth)
    elif t == "FunctionDef":
        for p in stmt.params:
            if p.default is not None:
                _annotate_calls_expr(p.default, depth)
        for s in stmt.body:
            _annotate_calls_stmt(s, depth + 1)
    elif t == "Return":
        if stmt.value is not None:
            _annotate_calls_expr(stmt.value, depth)
    elif t == "ExprStmt":
        _annotate_calls_expr(stmt.value, depth)


def build_context(root):
    """Annotate the parsed Module and return it (mutated in place)."""
    root_scope = Scope(None, "module")
    _build_scopes(root.body, root_scope, 0)
    root.scope_tree = root_scope
    for stmt in root.body:
        _annotate_calls_stmt(stmt, 0)
    return root
