#!/bin/bash
# Real oracle for gale-slate: write the CWE static-analyzer deliverable, then
# RUN it on the visible fixture to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
"""Static weakness analyzer: maps source patterns to CWE identifiers."""
import ast
import json
import sys

CWE_89, CWE_78, CWE_95 = "CWE-89", "CWE-78", "CWE-95"
CWE_502, CWE_327, CWE_798 = "CWE-502", "CWE-327", "CWE-798"
CWE_601, CWE_918 = "CWE-601", "CWE-918"

UNSAFE_LOADERS = {"pickle.load", "pickle.loads", "dill.load", "dill.loads",
                  "yaml.load"}
BROKEN_HASH = {"hashlib.md5", "hashlib.sha1"}
HTTP_CLIENTS = {"requests.get", "requests.post"}
CRED_MARKERS = ("password", "passwd", "secret", "api_key")


def is_str_literal(node):
    return isinstance(node, ast.Constant) and isinstance(node.value, str)


def dotted_name(node):
    """Return the dotted name of a Name/Attribute chain, else None."""
    parts = []
    cur = node
    while isinstance(cur, ast.Attribute):
        parts.append(cur.attr)
        cur = cur.value
    if isinstance(cur, ast.Name):
        parts.append(cur.id)
        return ".".join(reversed(parts))
    return None


def first_positional(call):
    if call.args:
        return call.args[0]
    for kw in call.keywords:
        if kw.arg == "url":
            return kw.value
    return None


def rules_for_call(call):
    """Return a list of CWE ids triggered by one Call node."""
    found = []
    func = call.func
    arg0 = call.args[0] if call.args else None

    # R1 CWE-89: dynamic SQL through an .execute(...) call
    if isinstance(func, ast.Attribute) and func.attr == "execute":
        if arg0 is not None and not is_str_literal(arg0):
            found.append(CWE_89)

    name = dotted_name(func)

    # R2 CWE-78: os.system / os.popen / subprocess with shell=True
    if name in ("os.system", "os.popen"):
        if arg0 is not None and not is_str_literal(arg0):
            found.append(CWE_78)
    elif name is not None and name.startswith("subprocess."):
        shell_true = any(
            kw.arg == "shell"
            and isinstance(kw.value, ast.Constant)
            and kw.value.value is True
            for kw in call.keywords
        )
        cmd = arg0
        if cmd is None:
            for kw in call.keywords:
                if kw.arg == "args":
                    cmd = kw.value
                    break
        if shell_true and cmd is not None and not is_str_literal(cmd):
            found.append(CWE_78)

    # R3 CWE-95: eval / exec on non-literal
    if isinstance(func, ast.Name) and func.id in ("eval", "exec"):
        if arg0 is not None and not is_str_literal(arg0):
            found.append(CWE_95)

    # R4 CWE-502: unsafe deserialization
    if name in UNSAFE_LOADERS:
        found.append(CWE_502)

    # R5 CWE-327: broken hash
    if name in BROKEN_HASH:
        found.append(CWE_327)

    # R7 CWE-601: open redirect
    if (isinstance(func, ast.Name) and func.id == "redirect") or (
            isinstance(func, ast.Attribute) and func.attr == "redirect"):
        if arg0 is not None and not is_str_literal(arg0):
            found.append(CWE_601)

    # R8 CWE-918: SSRF via requests
    if name in HTTP_CLIENTS:
        url = first_positional(call)
        if url is not None and not is_str_literal(url):
            found.append(CWE_918)

    return found


def rules_for_assign(node):
    """R6 CWE-798: hardcoded credential string literals."""
    targets = []
    if isinstance(node, ast.Assign) and len(node.targets) == 1:
        targets = [node.targets[0]]
    elif isinstance(node, ast.AnnAssign):
        targets = [node.target]
    value = node.value
    if value is None or not is_str_literal(value) or value.value == "":
        return []
    out = []
    for tgt in targets:
        if isinstance(tgt, ast.Name):
            low = tgt.id.lower()
            if any(marker in low for marker in CRED_MARKERS):
                out.append(CWE_798)
    return out


class ScopeWalker:
    def __init__(self):
        self.findings = set()

    def walk(self, node, scope):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                self.walk(child, child.name)
                continue
            if isinstance(child, ast.Call):
                for cwe in rules_for_call(child):
                    self.findings.add((scope, cwe))
            if isinstance(child, (ast.Assign, ast.AnnAssign)):
                for cwe in rules_for_assign(child):
                    self.findings.add((scope, cwe))
            self.walk(child, scope)


def main():
    src_path, out_path = sys.argv[1], sys.argv[2]
    with open(src_path, "r", encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), filename=src_path)
    walker = ScopeWalker()
    walker.walk(tree, "<module>")
    findings = [
        {"component": comp, "cwe": cwe}
        for comp, cwe in sorted(walker.findings)
    ]
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"findings": findings}, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the output.
python3 "$SOLVER" /app/report_service.py "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
