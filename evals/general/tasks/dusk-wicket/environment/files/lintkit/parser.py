"""Indentation-driven recursive-descent parser for the minipy subset.

The token stream (from ``lexer``) has no INDENT/DEDENT markers.  Block
structure is recovered by comparing the 1-based column of the first
significant token on each line: a compound statement's suite is made of the
following lines whose indent is strictly greater than the header's indent.
``elif`` / ``else`` / ``else:`` clauses are recognised when they sit at the
*exact* indent of the matching ``if`` header.  One statement per line
(no semicolons), so every statement has a unique start line; the parser
records all statement start lines on the returned Module so suppression's
"next statement" form can target the line that follows a directive.
"""

from lexer import tokenize, LintError
import ast_nodes as N

KEYWORDS = {"def", "if", "elif", "else", "for", "while", "return",
            "pass", "break", "continue", "in", "and", "or", "not",
            "True", "False", "None"}

AUG_OPS = {"+=", "-=", "*=", "/=", "%="}


class Parser(object):
    def __init__(self, text, file="<input>"):
        self.text = text
        self.file = file
        self.toks = tokenize(text)
        self.pos = 0
        self.stmt_start_lines = set()

    # -- token helpers -------------------------------------------------
    def peek(self, k=0):
        idx = self.pos + k
        if idx >= len(self.toks):
            idx = len(self.toks) - 1
        return self.toks[idx]

    def advance(self):
        t = self.toks[self.pos]
        if self.toks[self.pos][0] != "EOF":
            self.pos += 1
        return t

    def peek_is(self, kind, value=None):
        t = self.peek()
        if t[0] != kind:
            return False
        if value is not None and t[1] != value:
            return False
        return True

    def expect(self, kind, value=None):
        t = self.peek()
        if t[0] != kind or (value is not None and t[1] != value):
            raise LintError(
                "expected %s%s at %d:%d" % (
                    kind, "" if value is None else " %r" % value, t[2], t[3]))
        return self.advance()

    def next_real(self):
        """Return the next non-newline, non-comment token (no advance)."""
        while self.toks[self.pos][0] in ("COMMENT", "NEWLINE"):
            self.pos += 1
        return self.toks[self.pos]

    def at_line_end(self):
        """Return True when only comment/newline/EOF remain on this line."""
        j = self.pos
        while self.toks[j][0] in ("COMMENT", "NEWLINE"):
            return True
        return self.toks[j][0] == "EOF"

    def consume_line_end(self):
        while True:
            t = self.peek()
            if t[0] == "COMMENT":
                self.advance()
                continue
            if t[0] == "NEWLINE":
                self.advance()
                return
            if t[0] == "EOF":
                return
            raise LintError("unexpected %s at %d:%d" % (t[0], t[2], t[3]))

    # -- grammar --------------------------------------------------------
    def parse(self):
        body = self.parse_suite(-1)
        mod = N.Module(body, self.text, self.file)
        mod.stmt_start_lines = self.stmt_start_lines
        return mod

    def parse_suite(self, parent_indent):
        stmts = []
        while True:
            t = self.next_real()
            if t[0] == "EOF":
                break
            if t[3] <= parent_indent:
                break
            stmts.append(self.parse_statement())
        return stmts

    def parse_statement(self):
        t = self.next_real()
        if t[0] == "EOF":
            raise LintError("unexpected end of input")
        self.stmt_start_lines.add(t[2])
        if t[0] == "NAME" and t[1] in KEYWORDS:
            kw = t[1]
            if kw == "def":
                return self.parse_def()
            if kw == "if":
                return self.parse_if()
            if kw == "for":
                return self.parse_for()
            if kw == "while":
                return self.parse_while()
            if kw == "return":
                return self.parse_return()
            if kw == "pass":
                self.advance()
                self.consume_line_end()
                return N.Pass(t[2], t[3])
            if kw == "break":
                self.advance()
                self.consume_line_end()
                return N.Break(t[2], t[3])
            if kw == "continue":
                self.advance()
                self.consume_line_end()
                return N.Continue(t[2], t[3])
            if kw in ("elif", "else"):
                raise LintError("stray '%s' at %d:%d" % (kw, t[2], t[3]))
            # fall through: keyword as bare name? not allowed
            raise LintError("unexpected keyword '%s' at %d:%d" % (kw, t[2], t[3]))
        return self.parse_simple_statement()

    def parse_simple_statement(self):
        if self.is_assignment():
            return self.parse_assignment()
        line, col = self.peek()[2], self.peek()[3]
        expr = self.parse_expr()
        self.consume_line_end()
        return N.ExprStmt(expr, line, col)

    def is_assignment(self):
        t0 = self.peek()
        t1 = self.peek(1)
        return (t0[0] == "NAME"
                and t1[0] == "OP"
                and t1[1] in ("=", "+=", "-=", "*=", "/=", "%="))

    def parse_assignment(self):
        name = self.advance()
        op = self.advance()
        target = N.Name(name[1], name[2], name[3])
        value = self.parse_expr()
        self.consume_line_end()
        if op[1] == "=":
            return N.Assign(target, value, name[2], name[3])
        return N.AugAssign(target, op[1][:-1], value, name[2], name[3])

    def parse_def(self):
        tok = self.advance()  # 'def'
        name = self.expect("NAME")
        self.expect("OP", "(")
        params = []
        while True:
            if self.peek_is("OP", ")"):
                break
            pname = self.expect("NAME")
            default = None
            if self.peek_is("OP", "="):
                self.advance()
                default = self.parse_expr()
            params.append(N.Param(pname[1], default, pname[2], pname[3]))
            if self.peek_is("OP", ","):
                self.advance()
                continue
            break
        self.expect("OP", ")")
        self.expect("OP", ":")
        self.consume_line_end()
        body = self.parse_suite(tok[3])
        fd = N.FunctionDef(name[1], params, body, tok[2], tok[3])
        fd.name_line = name[2]
        fd.name_col = name[3]
        return fd

    def parse_if(self):
        tok = self.advance()  # 'if'
        if_indent = tok[3]
        test = self.parse_expr()
        self.expect("OP", ":")
        self.consume_line_end()
        body = self.parse_suite(if_indent)
        if_node = N.If(test, body, [], [], tok[2], tok[3])
        while True:
            t = self.next_real()
            if t[0] == "NAME" and t[1] == "elif" and t[3] == if_indent:
                self.advance()
                etest = self.parse_expr()
                self.expect("OP", ":")
                self.consume_line_end()
                ebody = self.parse_suite(if_indent)
                if_node.elifs.append((etest, ebody))
            elif t[0] == "NAME" and t[1] == "else" and t[3] == if_indent:
                self.advance()
                self.expect("OP", ":")
                self.consume_line_end()
                if_node.orelse = self.parse_suite(if_indent)
                break
            else:
                break
        return if_node

    def parse_for(self):
        tok = self.advance()  # 'for'
        target = self.expect("NAME")
        self.expect("NAME", "in")
        iter = self.parse_expr()
        self.expect("OP", ":")
        self.consume_line_end()
        body = self.parse_suite(tok[3])
        return N.For(N.Name(target[1], target[2], target[3]), iter,
                     body, tok[2], tok[3])

    def parse_while(self):
        tok = self.advance()  # 'while'
        test = self.parse_expr()
        self.expect("OP", ":")
        self.consume_line_end()
        body = self.parse_suite(tok[3])
        return N.While(test, body, tok[2], tok[3])

    def parse_return(self):
        tok = self.advance()  # 'return'
        if self.at_line_end():
            self.consume_line_end()
            return N.Return(None, tok[2], tok[3])
        value = self.parse_expr()
        self.consume_line_end()
        return N.Return(value, tok[2], tok[3])

    # -- expressions ---------------------------------------------------
    def parse_expr(self):
        return self.parse_or()

    def parse_or(self):
        line, col = self.peek()[2], self.peek()[3]
        values = [self.parse_and()]
        while self.peek_is("NAME", "or"):
            self.advance()
            values.append(self.parse_and())
        if len(values) == 1:
            return values[0]
        return N.BoolOp("or", values, line, col)

    def parse_and(self):
        line, col = self.peek()[2], self.peek()[3]
        values = [self.parse_not()]
        while self.peek_is("NAME", "and"):
            self.advance()
            values.append(self.parse_not())
        if len(values) == 1:
            return values[0]
        return N.BoolOp("and", values, line, col)

    def parse_not(self):
        line, col = self.peek()[2], self.peek()[3]
        if self.peek_is("NAME", "not"):
            self.advance()
            operand = self.parse_not()
            return N.UnaryOp("not", operand, line, col)
        return self.parse_comparison()

    def parse_comparison(self):
        line, col = self.peek()[2], self.peek()[3]
        left = self.parse_arith()
        ops = []
        comparators = []
        while True:
            t = self.peek()
            if t[0] == "OP" and t[1] in ("==", "!=", "<", ">", "<=", ">="):
                self.advance()
                ops.append(t[1])
                comparators.append(self.parse_arith())
            else:
                break
        if not ops:
            return left
        return N.Compare(left, ops, comparators, line, col)

    def parse_arith(self):
        left = self.parse_term()
        while True:
            t = self.peek()
            if t[0] == "OP" and t[1] in ("+", "-"):
                self.advance()
                left = N.BinOp(left, t[1], self.parse_term(), left.line, left.col)
            else:
                break
        return left

    def parse_term(self):
        left = self.parse_unary()
        while True:
            t = self.peek()
            if t[0] == "OP" and t[1] in ("*", "/", "%"):
                self.advance()
                left = N.BinOp(left, t[1], self.parse_unary(), left.line, left.col)
            else:
                break
        return left

    def parse_unary(self):
        t = self.peek()
        if t[0] == "OP" and t[1] in ("-", "+"):
            self.advance()
            return N.UnaryOp(t[1], self.parse_unary(), t[2], t[3])
        return self.parse_postfix()

    def parse_postfix(self):
        atom = self.parse_atom()
        while True:
            t = self.peek()
            if t[0] == "OP" and t[1] == ".":
                self.advance()
                n = self.expect("NAME")
                atom = N.Attribute(atom, n[1], atom.line, atom.col,
                                   n[2], n[3])
                continue
            if t[0] == "OP" and t[1] == "(":
                self.advance()
                args = []
                if not self.peek_is("OP", ")"):
                    args.append(self.parse_expr())
                    while self.peek_is("OP", ","):
                        self.advance()
                        args.append(self.parse_expr())
                self.expect("OP", ")")
                atom = make_call(atom, args)
                continue
            break
        return atom

    def parse_atom(self):
        t = self.peek()
        if t[0] == "NUMBER":
            self.advance()
            cls = N.Float if isinstance(t[1], float) else N.Int
            return cls(t[1], t[2], t[3])
        if t[0] == "STRING":
            self.advance()
            value = t[1][1:-1]
            return N.Str(value, t[2], t[3])
        if t[0] == "NAME":
            if t[1] == "True":
                self.advance()
                return N.Bool(True, t[2], t[3])
            if t[1] == "False":
                self.advance()
                return N.Bool(False, t[2], t[3])
            if t[1] == "None":
                self.advance()
                return N.NoneLit(t[2], t[3])
            self.advance()
            return N.Name(t[1], t[2], t[3])
        if t[0] == "OP" and t[1] == "(":
            self.advance()
            expr = self.parse_expr()
            self.expect("OP", ")")
            return expr
        if t[0] == "OP" and t[1] == "[":
            return self.parse_list()
        if t[0] == "OP" and t[1] == "{":
            return self.parse_braces()
        raise LintError("unexpected %s at %d:%d" % (t[0], t[2], t[3]))

    def parse_list(self):
        t = self.peek()
        self.advance()  # '['
        elts = []
        if not self.peek_is("OP", "]"):
            elts.append(self.parse_expr())
            while self.peek_is("OP", ","):
                self.advance()
                if self.peek_is("OP", "]"):
                    break
                elts.append(self.parse_expr())
        self.expect("OP", "]")
        return N.List(elts, t[2], t[3])

    def parse_braces(self):
        t = self.peek()
        self.advance()  # '{'
        if self.peek_is("OP", "}"):
            self.advance()
            return N.Dict([], [], t[2], t[3])  # {} empty dict
        first = self.parse_expr()
        if self.peek_is("OP", ":"):
            self.advance()
            keys = [first]
            values = [self.parse_expr()]
            while self.peek_is("OP", ","):
                self.advance()
                if self.peek_is("OP", "}"):
                    break
                keys.append(self.parse_expr())
                self.expect("OP", ":")
                values.append(self.parse_expr())
            self.expect("OP", "}")
            return N.Dict(keys, values, t[2], t[3])
        elts = [first]
        while self.peek_is("OP", ","):
            self.advance()
            if self.peek_is("OP", "}"):
                break
            elts.append(self.parse_expr())
        self.expect("OP", "}")
        return N.Set(elts, t[2], t[3])


def make_call(func, args):
    """Build a Call node, extracting the final callee name/anchor position.

    For ``name(args)`` the callee name is ``name`` itself and it is *not* an
    attribute form.  For ``a.b.c(args)`` the callee name is ``c`` and it *is*
    an attribute form; the anchor is the ``c`` token position.
    """
    if func.type == "Name":
        return N.Call(func, args, func.id, False,
                      func.line, func.col, func.line, func.col)
    # Attribute-form call: the final callee name is the OUTERMOST
    # attribute node's name (the parser builds chains outward).
    return N.Call(func, args, func.attr, True,
                  func.attr_line, func.attr_col, func.line, func.col)


def parse(text, file="<input>"):
    return Parser(text, file).parse()
