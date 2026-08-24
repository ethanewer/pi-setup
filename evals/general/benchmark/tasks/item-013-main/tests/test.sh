#!/bin/bash
# Verifier for item-013: run the built c0 on a hidden clab program, compare to
# an independent reference, and require the staged toolchain artifacts.
mkdir -p /logs/verifier

if [ ! -f /app/compcert-src/build/c0 ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

mkdir -p /tmp/t13
cp /tests/test_input.c /tmp/t13/in.c
cd /app/compcert-src
./build/c0 /tmp/t13/in.c /tmp/t13/out.txt

if [ ! -f /tmp/t13/out.txt ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'EOF'
import re

def eval_expr(s, vars_):
    toks = []
    for t in re.findall(r"\d+|[a-z]|[()+\-*]", s):
        toks.append(int(t) if t.isdigit() else t)
    i = 0
    def peek():
        return toks[i] if i < len(toks) else None
    def adv():
        nonlocal i
        t = toks[i]; i += 1; return t
    def parse_e():
        v = parse_t()
        while peek() in ('+', '-'):
            op = adv(); r = parse_t()
            v = v + r if op == '+' else v - r
        return v
    def parse_t():
        v = parse_f()
        while peek() == '*':
            adv(); v = v * parse_f()
        return v
    def parse_f():
        t = adv()
        if t == '(':
            v = parse_e()
            if peek() == ')':
                adv()
            return v
        if isinstance(t, int):
            return t
        return vars_.get(t, 0)
    return parse_e()

with open("/tests/test_input.c", "rb") as f:
    raw = f.read()
text = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n").decode("utf-8")

out = ["; wordsize 64"]
var = {}
for line in text.split("\n"):
    line = line.split("//", 1)[0].strip()
    if not line:
        continue
    m = re.match(r"([a-z])\s*=\s*(.*?)\s*;", line)
    if m:
        var[m.group(1)] = eval_expr(m.group(2), var)
        continue
    m = re.match(r"put\s+(.*?)\s*;", line)
    if m and m.group(1):
        out.append(str(eval_expr(m.group(1), var)))
expected = ("\n".join(out) + "\n").encode("utf-8")

got = open("/tmp/t13/out.txt", "rb").read()
norm = lambda b: b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
out_ok = 1 if norm(expected) == norm(got) else 0
have_cert = (1 if (__import__('os').path.exists("/app/compcert-src/build/cert.checked")
             and __import__('os').path.exists("/app/compcert-src/build/oextract.checked")) else 0)

if out_ok and have_cert:
    reward = 1.0
elif out_ok:
    reward = 0.5
else:
    reward = 0.0
open("/logs/verifier/reward.txt", "w").write(str(reward))
EOF