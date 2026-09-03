"""Tiny AST node types for minipy.

Every node exposes ``type``, ``line`` and ``col`` (1-based start position of
the construct's first token).  Compound nodes store their body as plain lists.
Structural helpers (children()/walk()) live in ``analyze``.
"""


class Node(object):
    type = "Node"

    def __init__(self, line=0, col=0):
        self.line = line
        self.col = col


class Module(Node):
    type = "Module"

    def __init__(self, body, text, file):
        Node.__init__(self, 1, 1)
        self.body = body
        self.text = text
        self.file = file
        self.stmt_start_lines = set()


class Param(Node):
    type = "Param"

    def __init__(self, name, default, line, col):
        Node.__init__(self, line, col)
        self.name = name
        self.default = default


class FunctionDef(Node):
    type = "FunctionDef"

    def __init__(self, name, params, body, line, col):
        Node.__init__(self, line, col)
        self.name = name
        self.params = params
        self.body = body


class Assign(Node):
    type = "Assign"

    def __init__(self, target, value, line, col):
        Node.__init__(self, line, col)
        self.target = target
        self.value = value


class AugAssign(Node):
    type = "AugAssign"

    def __init__(self, target, op, value, line, col):
        Node.__init__(self, line, col)
        self.target = target
        self.op = op
        self.value = value


class For(Node):
    type = "For"

    def __init__(self, target, iter, body, line, col):
        Node.__init__(self, line, col)
        self.target = target
        self.iter = iter
        self.body = body


class While(Node):
    type = "While"

    def __init__(self, test, body, line, col):
        Node.__init__(self, line, col)
        self.test = test
        self.body = body


class If(Node):
    type = "If"

    def __init__(self, test, body, elifs, orelse, line, col):
        Node.__init__(self, line, col)
        self.test = test
        self.body = body
        self.elifs = elifs  # list of (test, body)
        self.orelse = orelse


class Return(Node):
    type = "Return"

    def __init__(self, value, line, col):
        Node.__init__(self, line, col)
        self.value = value


class Pass(Node):
    type = "Pass"


class Break(Node):
    type = "Break"


class Continue(Node):
    type = "Continue"


class ExprStmt(Node):
    type = "ExprStmt"

    def __init__(self, value, line, col):
        Node.__init__(self, line, col)
        self.value = value


class Name(Node):
    type = "Name"

    def __init__(self, id, line, col):
        Node.__init__(self, line, col)
        self.id = id


class Attribute(Node):
    type = "Attribute"

    def __init__(self, value, attr, line, col, attr_line, attr_col):
        Node.__init__(self, line, col)
        self.value = value
        self.attr = attr
        self.attr_line = attr_line
        self.attr_col = attr_col


class Call(Node):
    type = "Call"

    def __init__(self, func, args, name, is_attr,
                 name_line, name_col, line, col):
        Node.__init__(self, line, col)
        self.func = func
        self.args = args
        self.name = name
        self.is_attr = is_attr
        self.name_line = name_line
        self.name_col = name_col


class List(Node):
    type = "List"

    def __init__(self, elts, line, col):
        Node.__init__(self, line, col)
        self.elts = elts


class Dict(Node):
    type = "Dict"

    def __init__(self, keys, values, line, col):
        Node.__init__(self, line, col)
        self.keys = keys
        self.values = values


class Set(Node):
    type = "Set"

    def __init__(self, elts, line, col):
        Node.__init__(self, line, col)
        self.elts = elts


class Int(Node):
    type = "Int"

    def __init__(self, value, line, col):
        Node.__init__(self, line, col)
        self.value = value


class Float(Node):
    type = "Float"

    def __init__(self, value, line, col):
        Node.__init__(self, line, col)
        self.value = value


class Str(Node):
    type = "Str"

    def __init__(self, value, line, col):
        Node.__init__(self, line, col)
        self.value = value


class Bool(Node):
    type = "Bool"

    def __init__(self, value, line, col):
        Node.__init__(self, line, col)
        self.value = value


class NoneLit(Node):
    type = "NoneLit"


class BinOp(Node):
    type = "BinOp"

    def __init__(self, left, op, right, line, col):
        Node.__init__(self, line, col)
        self.left = left
        self.op = op
        self.right = right


class BoolOp(Node):
    type = "BoolOp"

    def __init__(self, op, values, line, col):
        Node.__init__(self, line, col)
        self.op = op
        self.values = values


class Compare(Node):
    type = "Compare"

    def __init__(self, left, ops, comparators, line, col):
        Node.__init__(self, line, col)
        self.left = left
        self.ops = ops
        self.comparators = comparators


class UnaryOp(Node):
    type = "UnaryOp"

    def __init__(self, op, operand, line, col):
        Node.__init__(self, line, col)
        self.op = op
        self.operand = operand
