#!/bin/bash
set -euo pipefail

cat > /app/test_configs.py <<'PYEOF'
import sys
sys.path.insert(0, '/app')
import codegtool

cases = [
    ({"multiplier": 3, "offset": 1}, 5, 16),
    ({"multiplier": 2, "offset": 10}, 7, 24),
    ({"multiplier": -1, "offset": 100}, 42, 58),
    ({"multiplier": 4, "offset": 0}, 25, 100),
]

for cfg, value, expected in cases:
    got = codegtool.scaled_value(value, cfg)
    assert got == expected, (cfg, value, got, expected)

with open('/app/testresult.txt', 'w') as f:
    f.write("ALL_CONFIG_TESTS_PASS\n")
PYEOF

python3 /app/test_configs.py