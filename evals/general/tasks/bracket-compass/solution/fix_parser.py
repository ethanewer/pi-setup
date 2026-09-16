#!/usr/bin/env python3
"""Apply the required-block body check fix to src/jinja2/parser.py.

The pre-fix check iterated ``child.nodes`` of every body statement, assuming
every node exposes a ``.nodes`` attribute (true only for Output/TemplateData
nodes).  Statement nodes such as If or Block raised AttributeError before the
intended TemplateSyntaxError could be produced.  The fixed check verifies each
body node is an Output node and that all its TemplateData leaves are
whitespace before reporting "Required blocks can only contain comments or
whitespace".

Idempotent; exits non-zero if the expected pre-fix block is missing.
"""

import sys
from pathlib import Path

OLD = """        if node.required and not all(
            isinstance(child, nodes.TemplateData) and child.data.isspace()
            for body in node.body
            for child in body.nodes  # type: ignore
        ):
            self.fail("Required blocks can only contain comments or whitespace")"""

NEW = """        if node.required:
            for body_node in node.body:
                if not isinstance(body_node, nodes.Output) or any(
                    not isinstance(output_node, nodes.TemplateData)
                    or not output_node.data.isspace()
                    for output_node in body_node.nodes
                ):
                    self.fail("Required blocks can only contain comments or whitespace")"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_parser.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if NEW in src:
        print("parser.py already carries the Output-node body check")
        return 0
    if OLD not in src:
        print("FATAL: expected pre-fix required-block check not found", file=sys.stderr)
        return 1
    src = src.replace(OLD, NEW, 1)
    path.write_text(src, encoding="utf-8")
    print("applied required-block body check fix to parser.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())