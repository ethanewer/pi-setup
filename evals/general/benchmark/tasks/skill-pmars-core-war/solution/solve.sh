#!/bin/bash
set -euo pipefail

cat > /app/warrior.red <<'EOF'
; classic dwarf-style Core War warrior
    ADD #4, 3
    MOV 2, @2
    JMP -2
    DAT 0
EOF