#!/bin/bash
# Verifier for item-058-hard.
# Rewards 1 iff the file compiles, contains no cheating tokens (in code,
# ignoring comments), and declares exactly the five expected theorems in order.
# Else 0. Always writes /logs/verifier/reward.txt.

mkdir -p /logs/verifier
FILE=/app/arithmetic_hard.v
reward=0

if [ -f "$FILE" ]; then
  if (cd /app && coqc arithmetic_hard.v 2>/dev/null); then
    python3 - "$FILE" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
code = re.sub(r"\(\*.*?\*\)", "", text, flags=re.S)
forbidden = re.findall(r"\b(Require|Admitted|Admit|Axiom|Parameter|lia|omega)\b", code)
if forbidden:
    sys.exit(1)
decls = re.findall(r"^\s*(Lemma|Theorem)\s+(\w+)", code, re.M)
names = [n for _, n in decls]
expected = ["plus_n_O", "plus_n_Sm", "comm", "plus_assoc", "final_goal"]
other = re.findall(r"^\s*(?:Definition|Fixpoint|Inductive|Axiom|Parameter|Class|Structure)\s+\w+", code, re.M)
ok = (names == expected and not other)
sys.exit(0 if ok else 1)
PY
    if [ $? -eq 0 ]; then
      reward=1
    fi
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0