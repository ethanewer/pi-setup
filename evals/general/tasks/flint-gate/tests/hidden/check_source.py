#!/usr/bin/env python3
"""flint-gate hidden inspection: kernel bodies must be triton.language-only
with explicit reductions.

Fails (exit 1) when:
  - the text contains tl.sum / triton.language.sum (anywhere);
  - the text contains a .sum( method call (anywhere);
  - any @triton.jit function body calls the built-in sum(), or references
    torch / numpy / np / math, or imports those modules.
"""
import ast
import re
import sys

SRC = "/app/gated_norm.py"
FORBIDDEN_ROOTS = {"torch", "numpy", "np", "math"}


def is_jit_decorated(fn) -> bool:
    for dec in fn.decorator_list:
        node = dec.func if isinstance(dec, ast.Call) else dec
        # triton.jit / tl.jit / bare jit
        if isinstance(node, ast.Attribute) and node.attr == "jit":
            return True
        if isinstance(node, ast.Name) and node.id == "jit":
            return True
    return False


def main() -> int:
    try:
        src = open(SRC, encoding="utf-8").read()
    except OSError as exc:
        print("cannot read %s: %s" % (SRC, exc))
        return 1

    if re.search(r"\btl\s*\.\s*sum\b", src):
        print("forbidden helper: tl.sum present")
        return 1
    if re.search(r"\btriton\s*\.\s*language\s*\.\s*sum\b", src):
        print("forbidden helper: triton.language.sum present")
        return 1
    if re.search(r"\.sum\s*\(", src):
        print("forbidden helper: .sum( method call present")
        return 1

    try:
        tree = ast.parse(src)
    except SyntaxError as exc:
        print("syntax error: %s" % exc)
        return 1

    jit_fns = [n for n in ast.walk(tree)
               if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
               and is_jit_decorated(n)]
    if not jit_fns:
        print("no @triton.jit kernel found in the deliverable")
        return 1

    for fn in jit_fns:
        for node in ast.walk(fn):
            # imports of forbidden modules inside the kernel
            if isinstance(node, ast.Import):
                for alias in node.names:
                    root = alias.name.split(".")[0]
                    if root in FORBIDDEN_ROOTS:
                        print("kernel %s imports forbidden module %s"
                              % (fn.name, alias.name))
                        return 1
            if isinstance(node, ast.ImportFrom) and node.module:
                root = node.module.split(".")[0]
                if root in FORBIDDEN_ROOTS:
                    print("kernel %s imports from forbidden module %s"
                          % (fn.name, node.module))
                    return 1
            # built-in sum() calls
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
                    and node.func.id == "sum":
                print("kernel %s uses built-in sum()" % fn.name)
                return 1
            # attribute chains rooted at a forbidden name (torch.foo, np.bar...)
            n = node
            while isinstance(n, ast.Attribute):
                n = n.value
            if isinstance(n, ast.Name) and n.id in FORBIDDEN_ROOTS:
                print("kernel %s references forbidden name %s"
                      % (fn.name, n.id))
                return 1

    print("kernel inspection passed (%d jit kernel(s))" % len(jit_fns))
    return 0


if __name__ == "__main__":
    sys.exit(main())
