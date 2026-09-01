#!/usr/bin/env bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PY'
import json
CLS = {"MOV":"data","DAT":"data","DATX":"data",
       "ADD":"arith","SUB":"arith","MUL":"arith","DIV":"arith","MOD":"arith","SLT":"arith",
       "SPL":"split",
       "JMP":"jump","JMZ":"jump","JMN":"jump","DJN":"jump"}
exp=[]
for line in open("/app/warrior.rc"):
    line=line.strip()
    if not line or line.startswith(";"):
        continue
    toks=[t for t in line.replace(","," ").split() if t]
    op=toks[0].upper()
    a=toks[1] if len(toks)>1 else None
    b=toks[2] if len(toks)>2 else None
    exp.append({"op":op,"class":CLS.get(op,"?"),"a":a,"b":b})
got=json.load(open("/app/result.json"))
if got != exp:
    raise SystemExit((got, exp))
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt