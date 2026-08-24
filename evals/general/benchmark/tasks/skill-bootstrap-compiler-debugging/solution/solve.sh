#!/bin/bash
set -euo pipefail
cat > /app/compiler.py <<'PYEOF'
def tokenize(s):
    toks = []
    i = 0
    while i < len(s):
        c = s[i]
        if c.isspace():
            i += 1; continue
        if c.isdigit():
            j = i
            while j < len(s) and s[j].isdigit():
                j += 1
            toks.append(int(s[i:j])); i = j; continue
        if c in '()+-*':
            toks.append(c); i += 1; continue
        i += 1
    return toks

def parse(toks):
    pos = 0
    def expr():
        nonlocal pos
        val = term()
        while pos < len(toks) and toks[pos] in ('+', '-'):
            op = toks[pos]; pos += 1
            right = term()
            val = (val + right) if op == '+' else (val - right)
        return val
    def term():
        nonlocal pos
        val = factor()
        while pos < len(toks) and toks[pos] == '*':
            pos += 1
            val = val * factor()
        return val
    def factor():
        nonlocal pos
        t = toks[pos]
        if t == '(':
            pos += 1
            v = expr()
            pos += 1  # skip ')'
            return v
        pos += 1
        return t
    return expr()

def evaluate(line):
    return parse(tokenize(line))

def main():
    lines = [ln.strip() for ln in open('/app/src.txt') if ln.strip()]
    with open('/app/src_output.txt', 'w') as f:
        for ln in lines:
            f.write(str(evaluate(ln)) + chr(10))
if __name__ == '__main__':
    main()
PYEOF
python3 /app/compiler.py
