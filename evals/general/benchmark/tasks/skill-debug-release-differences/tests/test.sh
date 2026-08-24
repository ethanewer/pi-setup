#!/bin/bash
reward=0
mkdir -p /logs/verifier
dbg_out=""
rel_out=""
dbg_ok=0; rel_ok=0
if gcc /app/calc.c -o /tmp/v_dbg 2>/tmp/v_dbg.err; then
  dbg_out=$(/tmp/v_dbg 2>/dev/null) && dbg_ok=1
fi
if gcc -DNDEBUG /app/calc.c -o /tmp/v_rel 2>/tmp/v_rel.err; then
  rel_out=$(/tmp/v_rel 2>/dev/null) && rel_ok=1
fi
dbg_out=$(printf '%s' "$dbg_out" | tr -d '\r\n')
rel_out=$(printf '%s' "$rel_out" | tr -d '\r\n')
if [ "$dbg_ok" = 1 ] && [ "$rel_ok" = 1 ] && [ "$dbg_out" = "out=0" ] && [ "$rel_out" = "out=0" ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
