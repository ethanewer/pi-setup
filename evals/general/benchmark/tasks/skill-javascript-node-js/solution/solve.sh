#!/bin/bash
set -euo pipefail
cat > /app/main.js <<'EOF'
const fs = require('fs');
const nums = fs.readFileSync('/app/numbers.txt', 'utf8')
  .trim().split('\n').map(x => parseInt(x, 10));
const product = nums.reduce((a, b) => a * b, 1);
fs.writeFileSync('/app/product_output.txt', String(product) + '\n');
EOF
node /app/main.js