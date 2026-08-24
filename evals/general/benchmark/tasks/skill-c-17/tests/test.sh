#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/treewalk.cpp ]; then
  uses_fs=$(grep -c 'std::filesystem\|<filesystem>' /app/treewalk.cpp 2>/dev/null)
  if [ "$uses_fs" -gt 0 ] && g++ -std=c++17 -O2 -o /tmp/treewalk /app/treewalk.cpp 2>/tmp/gxx17.log; then
    # recompute expected sizes from the real tree
    expected_total=$(find /app/data -type f -printf '%s\n' | awk '{s+=$1} END{print s}')
    out=$(/tmp/treewalk /app/data)
    lines_ok=1
    while IFS= read -r f; do
      name=$(basename "$f")
      size=$(stat -c '%s' "$f")
      if ! echo "$out" | grep -qx "$name:$size"; then
        lines_ok=0
      fi
    done < <(find /app/data -type f)
    total_ok=0
    echo "$out" | tail -1 | grep -q "^total=${expected_total}$" && total_ok=1
    if [ "$lines_ok" = 1 ] && [ "$total_ok" = 1 ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt