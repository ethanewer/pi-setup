#!/usr/bin/env python3
"""Independent reference implementation for dusk-wicket.

This script REDERIVES the expected findings for a set of minipy sources with
its own fresh tokenizer, parser, rule logic and suppression engine — it does
NOT import anything under /app.  The evaluator runs the agent's deliverable
CLI (/app/lintkit/lint.py, /app/rules/forbid_call.py, /app/rules/shadow_var.py,
/app/rules/mut_default.py) on the same sources and compares the JSON.

Usage: python3 reference.py FILE...   ->  {path: [ {id,line,col,message}, ... ]}

The forbidden call-name set is FIXED by the task specification (mirrors
/app/rules/forbid_call.json); it is inlined here so the reference never trusts
agent/container state.
"""

import json
import re
import sys

FORBIDDEN = {"eval", "exec", "shell", "system", "popen", "network_open",
             "send_wire"}

# --------------------------------------------------------------------------
# tokenizer (minipy lexer, self-contained copy)
# --------------------------------------------------------------------------

NAME_RX = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUM_RX = re.compile(r"[0-9]+(?:\.[0-9]+)?")
STR_RX = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'')
OP_RX = re.compile(r"==|!=|<=|>=|\+=|-=|\*=|/=|%=|&&|\|\||[()\[\]{},:;=+\-*/%<>.]")


class RefError(Exception):
    pass


def tokenize(src):
    out = []
    pos = 0
    line = 1
    col = 1
    n = len(src)
    while pos < n:
        ch = src[pos]
        if ch in " \t":
            pos += 1
            col += 1
            continue
        if ch == "\n":
            out.append(("NEWLINE", "", line, col))
            pos += 1
            line += 1
            col = 1
            continue
        if ch == "#":
            start = pos
            while pos < n and src[pos] != "\n":
                pos += 1
            out.append(("COMMENT", src[start:pos], line, col))
            col += pos - start
            continue
        if ch in "\"'":
            m = STR_RX.match(src, pos)
            if not m:
                raise RefError("bad string %d:%d" % (line, col))
            out.append(("STRING", m.group(0), line, col))
            pos = m.end()
            col += len(m.group(0))
            continue
        if ch.isdigit():
            m = NUM_RX.match(src, pos)
            tok = m.group(0)
            out.append(("NUMBER", float(tok) if "." in tok else int(tok),
                        line, col))
            pos = m.end()
            col += len(tok)
            continue
        if ch.isalpha() or ch == "_":
            m = NAME_RX.match(src, pos)
            tok = m.group(0)
            out.append(("NAME", tok, line, col))
            pos = m.end()
            col += len(tok)
            continue
        m = OP_RX.match(src, pos)
        if m:
            tok = m.group(0)
            out.append(("OP", tok, line, col))
            pos = m.end()
            col += len(tok)
            continue
        raise RefError("unexpected %r" % ch)
    out.append(("EOF", "", line, col))
    return out


# --------------------------------------------------------------------------
# parser (recursive-descent, indentation driven)
# note: the reference uses independent node classes named after the grammar.
# --------------------------------------------------------------------------

KW = {"def", "if", "elif", "else", "for", "while", "return", "pass", "break",
      "continue", "in", "and", "or", "not"}


class P(object):
    def __init__(self, src):
        self.toks = tokenize(src)
        self.pos = 0
        self.starts = set()

    def peek(self, k=0):
        i = min(self.pos + k, len(self.toks) - 1)
        return self.toks[i]

    def advance(self):
        t = self.toks[self.pos]
        if self.toks[self.pos][0] != "EOF":
            self.pos += 1
        return t

    def is_op(self, k, val):
        t = self.peek(k)
        return t[0] == "OP" and t[1] == val

    def is_name(self, k, val):
        t = self.peek(k)
        return t[0] == "NAME" and t[1] == val

    def next_real(self):
        while self.toks[self.pos][0] in ("COMMENT", "NEWLINE"):
            self.pos += 1
        return self.toks[self.pos]

    def consume_eol(self):
        while True:
            t = self.peek()
            if t[0] == "COMMENT":
                self.advance()
            elif t[0] == "NEWLINE":
                self.advance()
                return
            elif t[0] == "EOF":
                return
            else:
                raise RefError("trailing %s" % (t,))

    # ---- statements ----
    def parse(self):
        body = self.suite(-1)
        return {"kind": "Module", "body": body,
                "starts": self.starts}

    def suite(self, parent):
        stmts = []
        while True:
            t = self.next_real()
            if t[0] == "EOF":
                break
            if t[3] <= parent:
                break
            stmts.append(self.stmt())
        return stmts

    def stmt(self):
        t = self.next_real()
        if t[0] == "EOF":
            raise RefError("eof")
        self.starts.add(t[2])
        if t[0] == "NAME" and t[1] in KW:
            if t[1] == "def":
                return self.defn()
            if t[1] == "if":
                return self.ifi()
            if t[1] == "for":
                return self.foor()
            if t[1] == "while":
                return self.while_()
            if t[1] == "return":
                self.advance()
                if self.at_eol():
                    self.consume_eol()
                    return {"kind": "Return", "value": None, "line": t[2],
                            "col": t[3]}
                v = self.expr()
                self.consume_eol()
                return {"kind": "Return", "value": v, "line": t[2], "col": t[3]}
            if t[1] in ("pass", "break", "continue"):
                self.advance()
                self.consume_eol()
                return {"kind": "Simple", "what": t[1], "line": t[2],
                        "col": t[3]}
            raise RefError("kw %s" % t[1])
        return self.simple()

    def at_eol(self):
        t = self.peek()
        return t[0] in ("COMMENT", "NEWLINE", "EOF")

    def is_assign(self):
        t0 = self.peek()
        t1 = self.peek(1)
        return (t0[0] == "NAME" and t1[0] == "OP"
                and t1[1] in ("=", "+=", "-=", "*=", "/=", "%="))

    def simple(self):
        if self.is_assign():
            name = self.advance()
            op = self.advance()
            val = self.expr()
            self.consume_eol()
            if op[1] == "=":
                return {"kind": "Assign", "name": name[1], "line": name[2],
                        "col": name[3], "value": val}
            return {"kind": "AugAssign", "name": name[1], "line": name[2],
                    "col": name[3], "value": val}
        line, col = self.peek()[2], self.peek()[3]
        e = self.expr()
        self.consume_eol()
        return {"kind": "ExprStmt", "value": e, "line": line, "col": col}

    def defn(self):
        tok = self.advance()  # def
        name = self.advance()
        self.advance()  # (
        params = []
        while not self.is_op(0, ")"):
            pn = self.advance()
            default = None
            if self.is_op(0, "="):
                self.advance()
                default = self.expr()
            params.append({"name": pn[1], "line": pn[2], "col": pn[3],
                           "default": default})
            if self.is_op(0, ","):
                self.advance()
        self.advance()  # )
        self.advance()  # :
        self.consume_eol()
        body = self.suite(tok[3])
        return {"kind": "FunctionDef", "name": name[1], "nl": name[2],
                "nc": name[3], "line": tok[2], "col": tok[3],
                "params": params, "body": body}

    def ifi(self):
        tok = self.advance()
        test = self.expr()
        self.advance()  # :
        self.consume_eol()
        body = self.suite(tok[3])
        elifs = []
        orelse = []
        while True:
            t = self.next_real()
            if t[0] == "NAME" and t[1] == "elif" and t[3] == tok[3]:
                self.advance()
                etest = self.expr()
                self.advance()
                self.consume_eol()
                elifs.append((etest, self.suite(tok[3])))
            elif t[0] == "NAME" and t[1] == "else" and t[3] == tok[3]:
                self.advance()
                self.advance()
                self.consume_eol()
                orelse = self.suite(tok[3])
                break
            else:
                break
        return {"kind": "If", "test": test, "body": body, "elifs": elifs,
                "orelse": orelse, "line": tok[2], "col": tok[3]}

    def foor(self):
        tok = self.advance()
        target = self.advance()
        self.advance()  # in
        it = self.expr()
        self.advance()  # :
        self.consume_eol()
        body = self.suite(tok[3])
        return {"kind": "For", "target": target[1], "tl": target[2],
                "tc": target[3], "iter": it, "body": body,
                "line": tok[2], "col": tok[3]}

    def while_(self):
        tok = self.advance()
        test = self.expr()
        self.advance()
        self.consume_eol()
        body = self.suite(tok[3])
        return {"kind": "While", "test": test, "body": body,
                "line": tok[2], "col": tok[3]}

    # ---- expressions ----
    def expr(self):
        return self.or_()

    def or_(self):
        values = [self.and_()]
        while self.is_name(0, "or"):
            self.advance()
            values.append(self.and_())
        return values[0] if len(values) == 1 else {"kind": "or", "values": values}

    def and_(self):
        values = [self.not_()]
        while self.is_name(0, "and"):
            self.advance()
            values.append(self.not_())
        return values[0] if len(values) == 1 else {"kind": "and", "values": values}

    def not_(self):
        if self.is_name(0, "not"):
            self.advance()
            return {"kind": "not", "operand": self.not_()}
        return self.cmp()

    def cmp(self):
        left = self.arith()
        ops = []
        comps = []
        while True:
            t = self.peek()
            if t[0] == "OP" and t[1] in ("==", "!=", "<", ">", "<=", ">="):
                self.advance()
                ops.append(t[1])
                comps.append(self.arith())
            else:
                break
        if not ops:
            return left
        return {"kind": "cmp", "left": left, "ops": ops, "comps": comps}

    def arith(self):
        left = self.term()
        while self.peek(0)[0] == "OP" and self.peek(0)[1] in ("+", "-"):
            op = self.advance()
            left = {"kind": "bin", "left": left, "op": op[1], "right": self.term()}
        return left

    def term(self):
        left = self.unary()
        while self.peek(0)[0] == "OP" and self.peek(0)[1] in ("*", "/", "%"):
            op = self.advance()
            left = {"kind": "bin", "left": left, "op": op[1],
                    "right": self.unary()}
        return left

    def unary(self):
        t = self.peek()
        if t[0] == "OP" and t[1] in ("-", "+"):
            self.advance()
            return {"kind": "un", "op": t[1], "operand": self.unary()}
        return self.postfix()

    def postfix(self):
        atom = self.atom()
        while True:
            t = self.peek()
            if t[0] == "OP" and t[1] == ".":
                self.advance()
                n = self.advance()
                atom = {"kind": "attr", "value": atom, "attr": n[1],
                        "al": n[2], "ac": n[3]}
                continue
            if t[0] == "OP" and t[1] == "(":
                self.advance()
                args = []
                if not self.is_op(0, ")"):
                    args.append(self.expr())
                    while self.is_op(0, ","):
                        self.advance()
                        args.append(self.expr())
                self.advance()  # )
                atom = self.makecall(atom, args)
                continue
            break
        return atom

    def makecall(self, func, args):
        if func["kind"] == "name":
            return {"kind": "call", "func": func, "args": args,
                    "name": func["name"], "is_attr": False,
                    "nl": func["line"], "nc": func["col"]}
        # Attribute form: final callee name is the OUTERMOST attr node.
        return {"kind": "call", "func": func, "args": args,
                "name": func["attr"], "is_attr": True,
                "nl": func["al"], "nc": func["ac"]}

    def atom(self):
        t = self.peek()
        if t[0] == "NUMBER":
            self.advance()
            return {"kind": "lit", "value": t[1], "line": t[2], "col": t[3]}
        if t[0] == "STRING":
            self.advance()
            return {"kind": "lit", "value": t[1], "line": t[2], "col": t[3]}
        if t[0] == "NAME":
            self.advance()
            if t[1] in ("True", "False", "None"):
                return {"kind": "lit", "value": t[1], "line": t[2], "col": t[3]}
            return {"kind": "name", "name": t[1], "line": t[2], "col": t[3]}
        if self.is_op(0, "("):
            self.advance()
            e = self.expr()
            self.advance()  # )
            return e
        if self.is_op(0, "["):
            return self.list_()
        if self.is_op(0, "{"):
            return self.braces()
        raise RefError("atom %s" % (t,))

    def list_(self):
        t = self.advance()  # [
        elts = []
        if not self.is_op(0, "]"):
            elts.append(self.expr())
            while self.is_op(0, ","):
                self.advance()
                if self.is_op(0, "]"):
                    break
                elts.append(self.expr())
        self.advance()  # ]
        return {"kind": "list", "elts": elts, "line": t[2], "col": t[3]}

    def braces(self):
        t = self.advance()  # {
        if self.is_op(0, "}"):
            self.advance()
            return {"kind": "dict", "line": t[2], "col": t[3]}
        first = self.expr()
        if self.is_op(0, ":"):
            self.advance()
            self.advance()  # value (parse & discard)
            while self.is_op(0, ","):
                self.advance()
                if self.is_op(0, "}"):
                    break
                self.expr()
                self.advance()  # :
                self.expr()
            self.advance()  # }
            return {"kind": "dict", "line": t[2], "col": t[3]}
        while self.is_op(0, ","):
            self.advance()
            if self.is_op(0, "}"):
                break
            self.expr()
        self.advance()  # }
        return {"kind": "set", "line": t[2], "col": t[3]}


def parse_src(src):
    return P(src).parse()


# --------------------------------------------------------------------------
# structural analysis: func_depth per call + scope tree (documented block
# model).  Independent implementation.
# --------------------------------------------------------------------------

class ScopeNode(object):
    def __init__(self, parent, kind):
        self.parent = parent
        self.kind = kind
        self.children = []
        self.bindings = []  # (name, node, kind)
        self.names = set()

    def child(self, kind="block"):
        c = ScopeNode(self, kind)
        self.children.append(c)
        return c

    def bind(self, name, node, kind):
        self.bindings.append((name, node, kind))
        self.names.add(name)


def expr_children(e):
    k = e.get("kind")
    if k == "call":
        return [e["func"]] + e["args"]
    if k == "attr":
        return [e["value"]]
    if k == "bin":
        return [e["left"], e["right"]]
    if k == "un":
        return [e["operand"]]
    if k == "not":
        return [e["operand"]]
    if k == "and" or k == "or":
        return list(e["values"])
    if k == "cmp":
        return [e["left"]] + list(e["comps"])
    if k == "list":
        return list(e["elts"])
    if k == "dict" or k == "set":
        return []
    return []


def annotate_calls_expr(e, depth):
    if e.get("kind") == "call":
        e["fdepth"] = depth
    for c in expr_children(e):
        annotate_calls_expr(c, depth)


def annotate_calls_stmt(s, depth):
    k = s["kind"]
    if k in ("Assign", "AugAssign"):
        annotate_calls_expr(s["value"], depth)
    elif k == "For":
        annotate_calls_expr(s["iter"], depth)
        for c in s["body"]:
            annotate_calls_stmt(c, depth)
    elif k == "While":
        annotate_calls_expr(s["test"], depth)
        for c in s["body"]:
            annotate_calls_stmt(c, depth)
    elif k == "If":
        annotate_calls_expr(s["test"], depth)
        for c in s["body"]:
            annotate_calls_stmt(c, depth)
        for et, eb in s["elifs"]:
            annotate_calls_expr(et, depth)
            for c in eb:
                annotate_calls_stmt(c, depth)
        for c in s["orelse"]:
            annotate_calls_stmt(c, depth)
    elif k == "FunctionDef":
        for p in s["params"]:
            if p["default"] is not None:
                annotate_calls_expr(p["default"], depth)
        for c in s["body"]:
            annotate_calls_stmt(c, depth + 1)
    elif k == "Return":
        if s["value"] is not None:
            annotate_calls_expr(s["value"], depth)
    elif k == "ExprStmt":
        annotate_calls_expr(s["value"], depth)


def build_scopes(stmts, scope, depth):
    for s in stmts:
        k = s["kind"]
        if k in ("Assign", "AugAssign"):
            scope.bind(s["name"], s, "assign")
        elif k == "For":
            scope.bind(s["target"],
                       {"kind": "synthetic", "line": s["tl"],
                        "col": s["tc"]}, "for")
            build_scopes(s["body"], scope.child(), depth)
        elif k == "While":
            build_scopes(s["body"], scope.child(), depth)
        elif k == "If":
            build_scopes(s["body"], scope.child(), depth)
            for _, eb in s["elifs"]:
                build_scopes(eb, scope.child(), depth)
            build_scopes(s["orelse"], scope.child(), depth)
        elif k == "FunctionDef":
            scope.bind(s["name"], s, "def")
            fn = scope.child("function")
            for p in s["params"]:
                fn.bind(p["name"], p, "param")
            build_scopes(s["body"], fn, depth + 1)


def analyze(mod):
    mod["scope"] = ScopeNode(None, "module")
    build_scopes(mod["body"], mod["scope"], 0)
    for s in mod["body"]:
        annotate_calls_stmt(s, 0)
    return mod


# --------------------------------------------------------------------------
# the three rules (independent implementations)
# --------------------------------------------------------------------------

def rule_forbid_call(mod):
    out = []
    def walk_stmt(s):
        k = s["kind"]
        if k in ("Assign", "AugAssign"):
            walk_expr(s["value"])
        elif k in ("For", "While", "If", "FunctionDef"):
            for c in s["body"]:
                walk_stmt(c)
            if k == "For":
                walk_expr(s["iter"])
            elif k == "While":
                walk_expr(s["test"])
            elif k == "If":
                walk_expr(s["test"])
                for et, eb in s["elifs"]:
                    walk_expr(et)
                    for c in eb:
                        walk_stmt(c)
                for c in s["orelse"]:
                    walk_stmt(c)
            elif k == "FunctionDef":
                for p in s["params"]:
                    if p["default"] is not None:
                        walk_expr(p["default"])
        elif k == "Return":
            if s["value"] is not None:
                walk_expr(s["value"])
        elif k == "ExprStmt":
            walk_expr(s["value"])

    def walk_expr(e):
        if e.get("kind") == "call":
            if e["name"] in FORBIDDEN and e.get("fdepth", 0) >= 1:
                out.append({"id": "forbid-call", "line": e["nl"],
                            "col": e["nc"],
                            "message": "forbidden call to %s" % e["name"]})
        for c in expr_children(e):
            walk_expr(c)

    for s in mod["body"]:
        walk_stmt(s)
    return out


def rule_mut_default(mod):
    out = []
    def walk(stmts):
        for s in stmts:
            k = s["kind"]
            if k == "FunctionDef":
                for p in s["params"]:
                    d = p["default"]
                    if d is not None and d.get("kind") in ("list", "dict", "set"):
                        out.append({"id": "mut-default", "line": p["line"],
                                    "col": p["col"],
                                    "message": "mutable default for %s" % p["name"]})
                walk(s["body"])
            elif k in ("For", "While", "If"):
                for c in s["body"]:
                    walk([c])
                if k == "If":
                    for _, eb in s["elifs"]:
                        walk(eb)
                    walk(s["orelse"])
    walk(mod["body"])
    return out


def rule_shadow_var(mod):
    out = []
    def visit(scope):
        ancestors = []
        s = scope.parent
        while s is not None:
            ancestors.append(s)
            s = s.parent
        for (name, node, kind) in scope.bindings:
            for anc in ancestors:
                if name in anc.names:
                    if node.get("kind") == "FunctionDef":
                        line, col = node["nl"], node["nc"]
                    else:
                        line, col = node["line"], node["col"]
                    out.append({"id": "shadow-var", "line": line, "col": col,
                                "message": "shadowing of %s" % name})
                    break
        for c in scope.children:
            visit(c)
    visit(mod["scope"])
    return out


# --------------------------------------------------------------------------
# suppression engine (independent)
# --------------------------------------------------------------------------

DINT = r"([A-Za-z0-9_-]+)"
_FORMS = (
    re.compile(r"^nolint-begin\(([^)]*)\)$"),
    re.compile(r"^nolint-end\(([^)]*)\)$"),
    re.compile(r"^nolint:next\(([^)]*)\)$"),
    re.compile(r"^nolint\(([^)]*)\)$"),
)


def parse_ids(inner):
    return [p.strip() for p in inner.split(",")
            if p.strip() and re.fullmatch(DINT, p.strip())]


def suppressed(mod):
    """Return {rule_id: set(lines)} from line/region/next directives."""
    line_by = {}
    begin_by = {}
    end_by = {}
    next_by = {}
    for tok in tokenize(mod.get("_text", "")):
        if tok[0] != "COMMENT":
            continue
        body = tok[1][1:].strip()
        ln = tok[2]
        for i, rx in enumerate(_FORMS):
            m = rx.match(body)
            if not m:
                continue
            ids = parse_ids(m.group(1))
            if i == 0:
                for rid in ids:
                    begin_by.setdefault(rid, []).append(ln)
            elif i == 1:
                for rid in ids:
                    end_by.setdefault(rid, []).append(ln)
            elif i == 2:
                for rid in ids:
                    next_by.setdefault(rid, []).append(ln)
            else:
                for rid in ids:
                    line_by.setdefault(rid, set()).add(ln)
            break
    text = mod.get("_text", "")
    last = text.count("\n") + (0 if text.endswith("\n") else 1)
    if last < 1:
        last = 1
    starts = mod["starts"]
    supp = {}
    all_ids = set(line_by) | set(begin_by) | set(next_by)
    for rid in all_ids:
        lines = set(line_by.get(rid, ()))
        # region: stack matched per id
        events = [(b, "b") for b in begin_by.get(rid, [])]
        events += [(e, "e") for e in end_by.get(rid, [])]
        events.sort()
        stack = []
        for ln, kind in events:
            if kind == "b":
                stack.append(ln)
            elif stack:
                start = stack.pop()
                lines.update(range(start, ln + 1))
        for start in stack:
            lines.update(range(start, last + 1))
        # next: suppress on the next statement start line after the directive
        for n in next_by.get(rid, []):
            for s in sorted(starts):
                if s > n:
                    lines.add(s)
                    break
        supp[rid] = lines
    return supp


def reference_findings(src):
    mod = analyze(parse_src(src))
    mod["_text"] = src
    cand = rule_forbid_call(mod) + rule_shadow_var(mod) + rule_mut_default(mod)
    supp = suppressed(mod)
    keep = [f for f in cand if f["line"] not in supp.get(f["id"], ())]
    keep.sort(key=lambda f: (f["line"], f["col"], f["id"], f["message"]))
    return keep


def main(argv):
    result = {}
    for path in argv:
        with open(path, "r", encoding="utf-8") as fh:
            result[path] = reference_findings(fh.read())
    json.dump(result, sys.stdout, sort_keys=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))