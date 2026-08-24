#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/src_output.txt ]; then
  if python3 - <<'PYEOF'
lines = [ln.strip() for ln in open('/app/src.txt') if ln.strip()]
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
def evaluate(s):
    toks = tokenize(s)
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
        if toks[pos] == '(':
            pos += 1
            v = expr()
            pos += 1
            return v
        v = toks[pos]; pos += 1
        return v
    return expr()
exp = [evaluate(ln) for ln in lines]
got = [int(x) for x in open('/app/src_output.txt').read().split()]
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt