#!/bin/bash
# Verifier for item-044: validates the reconstructed git repo state.
# Always writes /logs/verifier/reward.txt; reward = passes/7.
set -uo pipefail
mkdir -p /logs/verifier
cd /app
F=/tests/fixtures
pass=0; total=7

# 1. repository present, on main, clean working tree
if [ -d /app/arc-repo/.git ]; then
  br=$(git -C /app/arc-repo rev-parse --abbrev-ref HEAD 2>/dev/null || echo x)
  st=$(git -C /app/arc-repo status --porcelain 2>/dev/null || echo dirty)
  if [ "$br" = "main" ] && [ -z "$st" ]; then pass=$((pass+1)); fi
fi

# 2. fixed file content equals the expected fixed fixture
cmp -s /app/arc-repo/tasks/1e0a9b12.json "$F/expected_fixed_1e0a9b12.json" && pass=$((pass+1))
# 3. byou6dgf.json unchanged vs original fixture
[ -f /app/arc-repo/tasks/byou6dgf.json ] && cmp -s /app/arc-repo/tasks/byou6dgf.json "$F/original_byou6dgf.json" && pass=$((pass+1))
# 4. 3ccc3b22.json unchanged vs original fixture
[ -f /app/arc-repo/tasks/3ccc3b22.json ] && cmp -s /app/arc-repo/tasks/3ccc3b22.json "$F/original_3ccc3b22.json" && pass=$((pass+1))
# 5. corrupt file absent
[ ! -e /app/arc-repo/tasks/9e9ff3c4.json ] && pass=$((pass+1))
# 6. all remaining ARC files pass the schema validator
if [ -d /app/arc-repo/tasks ]; then
  python3 /tests/validate_arc.py /app/arc-repo/tasks >/dev/null 2>&1 && pass=$((pass+1))
fi
# 7. the bundle still verifies
git -C /app/arc-repo bundle verify /app/arc-repo.bundle >/dev/null 2>&1 && pass=$((pass+1))

reward=$(python3 -c "print(round($pass/$total,2))")
echo "$reward" > /logs/verifier/reward.txt