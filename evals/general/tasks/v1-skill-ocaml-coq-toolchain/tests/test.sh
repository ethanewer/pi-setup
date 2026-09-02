#!/bin/bash
# Verifier for skill-ocaml-coq-toolchain.
# Reward 1: coqc compiles the agent's my_probe.v (and .vo exists, no cheating tokens)
#           AND tool_chain.txt reports 42.
# Reward 0.5: only one of the two parts passes.
mkdir -p /logs/verifier
reward=0

PART_COQ=0
PART_OCAML=0

# ---- Part 1: Coq ----
if [ -f /app/my_probe.v ] && (cd /app && coqc my_probe.v >/dev/null 2>&1) && [ -f /app/my_probe.vo ]; then
  python3 - /app/my_probe.v <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
code = re.sub(r"\(\*.*?\*\)", "", text, flags=re.S)
forbidden = re.findall(r"\b(Admitted|Admit|Axiom|Require|Parameter)\b", code)
sys.exit(0 if not forbidden else 1)
PY
  [ $? -eq 0 ] && PART_COQ=1
fi

# ---- Part 2: OCaml ----
if [ -f /app/tool_chain.txt ]; then
  val=$(cat /app/tool_chain.txt | tr -d '[:space:]')
  if [ "$val" = "42" ]; then
    PART_OCAML=1
  fi
fi

if [ "$PART_COQ" -eq 1 ] && [ "$PART_OCAML" -eq 1 ]; then
  reward=1
elif [ "$PART_COQ" -eq 1 ] || [ "$PART_OCAML" -eq 1 ]; then
  reward=0.5
else
  reward=0
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0