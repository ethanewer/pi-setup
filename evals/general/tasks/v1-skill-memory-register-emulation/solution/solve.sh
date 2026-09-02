#!/bin/bash
set -euo pipefail
cat > /app/vm.py <<'EOF'
import json
regs={"R0":0,"R1":0,"R2":0,"R3":0}
mem=[0]*8
for line in open('/app/program.txt'):
    tok=line.split()
    if not tok: continue
    op=tok[0]
    if op=="LDI": regs[tok[1]]=int(tok[2])
    elif op=="ADD": regs[tok[1]]=regs[tok[2]]+regs[tok[3]]
    elif op=="SUB": regs[tok[1]]=regs[tok[2]]-regs[tok[3]]
    elif op=="MUL": regs[tok[1]]=regs[tok[2]]*regs[tok[3]]
    elif op=="MOV": regs[tok[1]]=regs[tok[2]]
    elif op=="STORE": mem[int(tok[1])]=regs[tok[2]]
    elif op=="LOAD": regs[tok[1]]=mem[int(tok[2])]
    elif op=="HLT": break
json.dump(regs, open('/app/reg.json','w'))
print(regs)
EOF
python3 /app/vm.py