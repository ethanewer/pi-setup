#!/usr/bin/env bash
#
# Oracle solution for hollow-dial. Performs the real work: authors the three
# deliverables (a header-based architecture classifier, a MIPS32 ELF
# interpreter, and a self-interpreting Liz evaluator), then RUNS them to
# produce the report/output artifacts. Never reads /tests.
set -euo pipefail

py=/usr/bin/python3
[ -x "$py" ] || py=python3

echo "[solve] 1) architecture classifier"
cp /solution/classify.py /app/classify.py
chmod +x /app/classify.py
"$py" /app/classify.py /app/samples/sum.pdp11 > /app/arch_report.json

echo "[solve] 2) MIPS ELF interpreter"
cp /solution/mips_interp.c /app/mips_interp.c
gcc -O2 -o /app/mips_interp /app/mips_interp.c
/app/mips_interp /app/samples/greet.mips > /app/mips_out.txt

echo "[solve] 3) Liz evaluator + one-level self-interpretation"
cp /solution/eval.py /app/eval.py
chmod +x /app/eval.py
# direct execution of the target
"$py" /app/eval.py /app/samples/fib.lsp > /tmp/direct.txt
# same target through the meta-circular (self-host) harness
"$py" /app/eval.py /app/samples/self.lsp > /tmp/hosted.txt
cmp -s /tmp/direct.txt /tmp/hosted.txt
cp /tmp/hosted.txt /app/self_host.txt

echo "[solve] done"