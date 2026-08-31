#!/bin/bash
# Real oracle for cinder-forge: write the scan.py static analyzer, then RUN it
# on the visible fixture to produce /app/findings.json. Never reads /tests.
set -eu

SCANNER="/app/scan.py"
OUT="/app/findings.json"

cat > "$SCANNER" <<'PY'
"""BridgePay static audit scanner: line-based CWE rule engine."""
import json
import re
import sys

RULE_CWE = {
    "command-injection": "CWE-78",
    "hardcoded-credential": "CWE-798",
    "sql-injection": "CWE-89",
    "unsafe-deserialization": "CWE-502",
    "weak-hash": "CWE-327",
}

RE_ASSIGN = re.compile(r"^\s*(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)\s*=(?!=)\s*(.+)$")
RE_PLAIN_LIT = re.compile(r"^[rbuRBU]{0,2}('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\")$")
RE_FSTRING = re.compile(r"^[fF][rbuRBU]{0,2}['\"]")
RE_CRED_NAME = re.compile(
    r"(password|passwd|secret|token|api_key|apikey|access_key)", re.I
)
RE_CMD_CALL = re.compile(r"\bos\.(?:system|popen)\s*\(")
RE_EXECUTE = re.compile(r"\.execute\s*\(")
RE_PICKLE = re.compile(r"\bpickle\.(?:loads|load)\s*\(")
RE_YAML_LOAD = re.compile(r"\byaml\.load\s*\(")
RE_SAFE_LOADER = re.compile(r"Loader\s*=\s*(?:yaml\.)?SafeLoader\b")
RE_WEAK_HASH = re.compile(r"\bhashlib\.(?:md5|sha1)\s*\(")


def first_arg(line, open_idx):
    """Text of the first argument of the call whose '(' is at open_idx."""
    depth = 0
    for i in range(open_idx, len(line)):
        ch = line[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return _split_top_comma(line[open_idx + 1 : i])
    return _split_top_comma(line[open_idx + 1 :])


def _split_top_comma(inner):
    depth = 0
    for i, ch in enumerate(inner):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            return inner[:i]
    return inner


def is_plain_literal(expr):
    expr = expr.strip()
    if RE_FSTRING.match(expr):
        return False
    return bool(RE_PLAIN_LIT.match(expr)) and expr.lstrip("rbuRBU\"'") != ""


def yaml_call_has_safe_loader(line, open_idx):
    depth = 0
    for i in range(open_idx, len(line)):
        ch = line[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return bool(RE_SAFE_LOADER.search(line[open_idx + 1 : i]))
    return bool(RE_SAFE_LOADER.search(line[open_idx + 1 :]))


def findings_for_line(line, lineno):
    found = []
    # rule 5: weak-hash
    if RE_WEAK_HASH.search(line):
        found.append(("weak-hash", lineno))
    # rule 4: unsafe-deserialization
    m = RE_PICKLE.search(line)
    if m:
        arg = first_arg(line, m.end() - 1)
        if not is_plain_literal(arg):
            found.append(("unsafe-deserialization", lineno))
    m = RE_YAML_LOAD.search(line)
    if m and not yaml_call_has_safe_loader(line, m.end() - 1):
        found.append(("unsafe-deserialization", lineno))
    # rule 3: sql-injection
    m = RE_EXECUTE.search(line)
    if m:
        arg = first_arg(line, m.end() - 1)
        if not is_plain_literal(arg):
            found.append(("sql-injection", lineno))
    # rule 2: command-injection
    m = RE_CMD_CALL.search(line)
    if m:
        arg = first_arg(line, m.end() - 1)
        if not is_plain_literal(arg):
            found.append(("command-injection", lineno))
    # rule 1: hardcoded-credential
    m = RE_ASSIGN.match(line)
    if m:
        name, rhs = m.group(1), m.group(2)
        if RE_CRED_NAME.search(name) and is_plain_literal(rhs):
            found.append(("hardcoded-credential", lineno))
    return found


def main():
    src_path, out_path = sys.argv[1], sys.argv[2]
    with open(src_path, "r", encoding="utf-8") as fh:
        text = fh.read()

    found = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        found.extend(findings_for_line(raw, lineno))

    # sort by line, then rule name; dedupe identical (rule, line) pairs
    seen = set()
    findings = []
    for rule, lineno in sorted(found, key=lambda t: (t[1], t[0])):
        if (rule, lineno) in seen:
            continue
        seen.add((rule, lineno))
        findings.append(
            {"line": lineno, "rule": rule, "cwe": RULE_CWE[rule]}
        )

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"findings": findings}, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SCANNER"

python3 "$SCANNER" /app/billing_api.py "$OUT"

echo "solve.sh done -> $SCANNER and $OUT"
ls -l "$SCANNER" "$OUT"
