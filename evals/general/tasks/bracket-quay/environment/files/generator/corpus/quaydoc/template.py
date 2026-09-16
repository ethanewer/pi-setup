"""A small, safe template engine.

Supports just enough for quaydoc's own themes (and for user templates):

================  ================================================
``{{ expr }}``           interpolate with ``|lower |upper |escape |default(x)``
``{% if expr %}``        truthiness, ``elif`` / ``else`` / ``endif``
``{% for x in xs %}``    with ``loop.index / loop.first / loop.last``
``{% include "name" %}`` include another template from the loader
================  ================================================

Expressions are dotted attribute/item lookups over the context, plus
literals and ``not``.  Unknown variables render as an empty string rather
than raising, which matches the rest of quaydoc's leniency; malformed tags
raise :class:`TemplateError` at compile time.
"""

from __future__ import annotations

import re

from quaydoc.errors import TemplateError
from quaydoc.util import escape_html

_TOKEN_RE = re.compile(r"(\{\{[^}]*\}\}|\{%[^%]*%\})", re.S)
_VAR_RE = re.compile(r"\{\{\s*([^}]+?)\s*\}\}")
_TAG_RE = re.compile(r"\{%\s*([^%]+?)\s*%\}")


def truthy(value):
    if value is None or value is False:
        return False
    if isinstance(value, (str, list, tuple, dict, set)):
        return len(value) > 0
    if isinstance(value, (int, float)):
        return value != 0
    return True


class Node:
    def render(self, context, loader):
        raise NotImplementedError


class TextNode(Node):
    def __init__(self, text):
        self.text = text

    def render(self, context, loader):
        return self.text


class VarNode(Node):
    def __init__(self, expr):
        parts = [p.strip() for p in expr.split("|")]
        self.expression = parts[0]
        self.filters = parts[1:]

    def render(self, context, loader):
        value = evaluate(self.expression, context)
        for filt in self.filters:
            value = apply_filter(filt, value)
        if value is None:
            return ""
        return str(value)


class IfNode(Node):
    def __init__(self, branches):
        self.branches = branches  # [(expression_or_None, [Node])]

    def render(self, context, loader):
        for expr, body in self.branches:
            if expr is None or truthy(evaluate(expr, context)):
                return "".join(n.render(context, loader) for n in body)
        return ""


class ForNode(Node):
    def __init__(self, varname, iterable_expr, body, else_body):
        self.varname = varname
        self.iterable_expr = iterable_expr
        self.body = body
        self.else_body = else_body

    def render(self, context, loader):
        items = evaluate(self.iterable_expr, context)
        if items is None:
            items = []
        out = []
        local = dict(context)
        for index, item in enumerate(items):
            local[self.varname] = item
            local["loop"] = {
                "index": index + 1, "index0": index,
                "first": index == 0, "last": index == len(items) - 1,
                "length": len(items),
            }
            out.append("".join(n.render(local, loader) for n in self.body))
        if not out and self.else_body:
            return "".join(n.render(dict(context), loader)
                           for n in self.else_body)
        return "".join(out)


class CommentNode(Node):
    def __init__(self, text):
        self.text = text

    def render(self, context, loader):
        return ""


class SetNode(Node):
    def __init__(self, varname, expr):
        self.varname = varname
        self.expr = expr

    def render(self, context, loader):
        context[self.varname] = evaluate(self.expr, context)
        return ""


class IncludeNode(Node):
    def __init__(self, name):
        self.name = name

    def render(self, context, loader):
        if not loader:
            return ""
        template = loader.get(self.name)
        if template is None:
            return ""
        return template.render(context, loader)


class Template:
    """Compiled template text, renderable against a context dict."""

    def __init__(self, text, name="<template>"):
        self.name = name
        self.nodes = _parse(text, name)

    def render(self, context=None, loader=None):
        shared = dict(context or {})
        return "".join(n.render(shared, loader) for n in self.nodes)


# ---------------------------------------------------------------------------
# compiler (recursive descent over a flat token stream)
# ---------------------------------------------------------------------------

def _scan(text, name):
    items = []
    pos = 0
    for m in _TOKEN_RE.finditer(text):
        if m.start() > pos:
            items.append(("text", text[pos:m.start()]))
        token = m.group(0)
        if token.startswith("{{"):
            vm = _VAR_RE.match(token)
            items.append(("var", vm.group(1)))
        else:
            tm = _TAG_RE.match(token)
            items.append(("tag", tm.group(1).strip()))
        pos = m.end()
    if pos < len(text):
        items.append(("text", text[pos:]))
    return items


def _parse(text, name):
    return _parse_nodes(_scan(text, name), 0, name, set(), stop_elif=False)[0]


def _parse_nodes(items, i, name, stops, stop_elif):
    """Parse nodes until a stop tag is seen (or EOF)."""
    nodes = []
    while i < len(items):
        kind, value = items[i]
        if kind == "text":
            nodes.append(TextNode(value))
            i += 1
            continue
        if kind == "var":
            nodes.append(VarNode(value))
            i += 1
            continue
        # tags
        tag = value
        if tag in stops or (stop_elif and tag.startswith("elif ")):
            return nodes, i
        if tag.startswith("if "):
            node, i = _parse_if(items, i, name)
            nodes.append(node)
        elif tag.startswith("for "):
            node, i = _parse_for(items, i, name)
            nodes.append(node)
        elif tag.startswith("include "):
            quoted = tag[len("include "):].strip()
            if not (quoted.startswith('"') and quoted.endswith('"')):
                raise TemplateError(
                    f"{name}: include needs a quoted template name")
            nodes.append(IncludeNode(quoted[1:-1]))
            i += 1
        elif tag.startswith("set "):
            sm = re.match(r"^set\s+([A-Za-z_]\w*)\s*=\s*(.+)$", tag)
            if not sm:
                raise TemplateError(f"{name}: bad set tag {tag!r}")
            nodes.append(SetNode(sm.group(1), sm.group(2)))
            i += 1
        elif tag == "comment":
            depth = 1
            i += 1
            while i < len(items) and depth:
                value = items[i][1]
                if value == "comment":
                    depth += 1
                elif value == "endcomment":
                    depth -= 1
                i += 1
            nodes.append(CommentNode(""))
        elif tag == "raw":
            pending = []
            i += 1
            while i < len(items) and items[i][1] != "endraw":
                pending.append(items[i])
                i += 1
            nodes.append(TextNode(_raw_body(pending)))
            i += 1
        else:
            raise TemplateError(f"{name}: unknown tag {tag!r}")
    if stops:
        raise TemplateError(f"{name}: missing {' or '.join(sorted(stops))}")
    return nodes, i


def _parse_if(items, i, name):
    expr = items[i][1][len("if "):].strip()
    branches = []
    body = []
    i += 1
    while True:
        if i >= len(items):
            raise TemplateError(f"{name}: if without endif")
        kind, value = items[i]
        if kind == "tag" and value == "endif":
            branches.append((expr, body))
            return IfNode(branches), i + 1
        if kind == "tag" and value == "else":
            branches.append((expr, body))
            else_body, i = _parse_nodes(items, i + 1, name, {"endif"},
                                        stop_elif=False)
            branches.append((None, else_body))
            if i < len(items) and items[i][1] == "endif":
                return IfNode(branches), i + 1
            raise TemplateError(f"{name}: if/else without endif")
        if kind == "tag" and value.startswith("elif "):
            branches.append((expr, body))
            expr = value[len("elif "):].strip()
            body = []
            i += 1
            continue
        node, i = _parse_nodes(items, i, name, {"endif", "else"},
                               stop_elif=True)
        body.extend(node)


def _parse_for(items, i, name):
    m = re.match(r"^for\s+([A-Za-z_]\w*)\s+in\s+(.+)$", items[i][1])
    if not m:
        raise TemplateError(f"{name}: bad for tag {items[i][1]!r}")
    varname, expr = m.group(1), m.group(2).strip()
    body, i = _parse_nodes(items, i + 1, name, {"endfor"}, stop_elif=False)
    if i < len(items) and items[i][1] == "endfor":
        return ForNode(varname, expr, body, []), i + 1
    raise TemplateError(f"{name}: for without endfor")


# ---------------------------------------------------------------------------
# expression evaluation
# ---------------------------------------------------------------------------

_ATOM = re.compile(
    r"^\s*(?:"
    r"('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\")"     # string literal
    r"|(\d+(?:\.\d+)?)"                              # number
    r"|(true|false|True|False|None|null|nil)"        # literal keyword
    r"|([A-Za-z_][\w.]*)"                            # dotted path
    r")\s*$")
_CMP_RE = re.compile(
    r"^\s*([A-Za-z_][\w.]*)\s*(==|!=|in)\s*(.+?)\s*$")


def evaluate(expr, context):
    expr = expr.strip()
    m = _ATOM.match(expr)
    if m:
        quoted, number, literal, path = m.groups()
        if quoted is not None:
            return _unquote(quoted)
        if number is not None:
            return float(number) if "." in number else int(number)
        if literal is not None:
            return {"true": True, "false": False, "True": True,
                    "False": False, "None": None, "null": None,
                    "nil": None}.get(literal)
        return _lookup(path, context)
    if expr.startswith("not "):
        return not truthy(evaluate(expr[4:], context))
    cm = _CMP_RE.match(expr)
    if cm:
        left_val = _lookup(cm.group(1), context)
        right_val = evaluate(cm.group(3), context)
        if cm.group(2) == "==":
            return left_val == right_val
        if cm.group(2) == "!=":
            return left_val != right_val
        if cm.group(2) == "in":
            try:
                return left_val in right_val
            except TypeError:
                return False
    return None


def _unquote(quoted):
    body = quoted[1:-1]
    return (body.replace("\\n", "\n").replace("\\t", "\t")
            .replace('\\"', '"').replace("\\'", "'").replace("\\\\", "\\"))


def _lookup(path, context):
    value = context
    for part in path.split("."):
        if part == "":
            return None
        if isinstance(value, dict):
            value = value.get(part)
        else:
            value = getattr(value, part, None)
        if value is None:
            return None
    return value


_FILTER_NAMES = (
    "lower", "upper", "title", "escape", "default", "capitalize",
    "length", "reverse", "strip", "trim", "join", "replace", "truncate",
)


def apply_filter(filt, value):
    m = re.match(r"^([a-z_]+)(?:\((.*)\))?$", filt.strip())
    if not m:
        return value
    kind, arg = m.group(1), m.group(2)
    if kind == "lower":
        return str(value).lower()
    if kind == "upper":
        return str(value).upper()
    if kind == "title":
        return str(value).title()
    if kind == "capitalize":
        text = str(value)
        return text[:1].upper() + text[1:] if text else ""
    if kind == "escape":
        return escape_html(str(value))
    if kind == "default":
        if value in (None, "", [], {}):
            return _unquote(arg) if arg is not None else ""
        return value
    if kind == "length":
        return len(value)
    if kind == "reverse":
        return value[::-1]
    if kind == "strip" or kind == "trim":
        return str(value).strip()
    if kind == "join":
        sep = _unquote(arg) if arg is not None else ", "
        return sep.join(str(item) for item in value)
    if kind == "replace":
        if arg is None or "," not in arg:
            return value
        old, _, new = arg.partition(",")
        return str(value).replace(_unquote(old), _unquote(new))
    if kind == "truncate":
        limit = int(_unquote(arg)) if arg is not None else 80
        text = str(value)
        return text[:limit] + ("…" if len(text) > limit else "")
    return value

def _raw_body(items):
    """Reconstruct literal template source for a ``{% raw %}`` body."""
    out = []
    var = re.compile(r"\{\{([^}]*?)\}\}")
    for kind, value in items:
        if kind == "text":
            out.append(value)
        elif kind == "var":
            out.append("{{" + value + "}}")
        else:
            out.append("{%" + value + "%}")
    return "".join(out)
