#!/bin/bash
# Verifier for item-058-main.
# Rewards 1 iff /app/arithmetic.v compiles under coqc with no cheating tokens
# (in code, not in comments) and the three declarations appear in order.
# Otherwise 0. Always writes /logs/verifier/reward.txt.

mkdir -p /logs/verifier
FILE=/app/arithmetic.v
reward=0

if [ -f "$FILE" ]; then
  if (cd /app && coqc arithmetic.v 2>/dev/null); then
    python3 - "$FILE" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
code = re.sub(r"\(\*.*?\*\)", "", text, flags=re.S)
forbidden = re.findall(r"\b(Require|Admitted|Admit|Axiom|Parameter|lia|omega)\b", code)
if forbidden:
    sys.exit(1)
decls = re.findall(r"^\s*(Lemma|Theorem)\s+(\w+)", code, re.M)
names = [n for _, n in decls]
pos = [i for i, n in enumerate(names) if n in ("plus_n_O", "plus_n_Sm", "add_comm")]
expected = ["plus_n_O", "plus_n_Sm", "add_comm"]
ok = (len(pos) == 3 and names[pos[0]] == "plus_n_O" and names[pos[1]] == "plus_n_Sm"
      and names[pos[2]] == "add_comm")
sys.exit(0 if ok else 1)
PY
    if [ $? -eq 0 ]; then
      reward=1
    fi
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0