#!/bin/bash
set -euo pipefail
# G1 segments: (5,5)->(30,5)=25; (30,5)->(30,20)=15; (30,20)->(5,20)=25; (5,20)->(5,30)=10
# Total = 25+15+25+10 = 75
cat > /app/answer.json <<'EOF'
{"total_extruded_length": 75}
EOF
echo "wrote answer.json"