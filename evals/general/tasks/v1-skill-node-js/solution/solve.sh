#!/bin/bash
set -euo pipefail

cat > /app/process.js <<'EOF'
const fs = require('fs');

const records = JSON.parse(fs.readFileSync('/app/input.json', 'utf8'));
// stabilize by inserting original index, then sort desc by score
const indexed = records.map((r, i) => ({name: r.name, score: r.score, i}));
indexed.sort((a, b) => (b.score - a.score) || (a.i - b.i));
const names = indexed.map(r => r.name);

fs.writeFileSync('/app/out.json', JSON.stringify(names));
EOF

node /app/process.js