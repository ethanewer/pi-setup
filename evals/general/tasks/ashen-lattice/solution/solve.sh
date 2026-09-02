#!/bin/bash
# Oracle for ashen-lattice: install the real pure-JS decision module and
# batch driver (the genuine work), smoke-check the interface contract, then
# RUN the driver on the visible fixture to produce /app/walkthrough.json.
# Never reads /tests.
set -euo pipefail
mkdir -p /app

cp /solution/drone.js /app/drone.js
cp /solution/simulate.js /app/simulate.js
chmod +x /app/drone.js /app/simulate.js

# Static contract: no require( / import anywhere in the pure module.
if grep -q 'require(' /app/drone.js || grep -qE '(^|[^A-Za-z0-9_.])import( |")' /app/drone.js; then
  echo "oracle: drone.js violates the no-import contract" >&2
  exit 1
fi

# Interface smoke: exports { choose } as a plain one-arg function, and a
# known state decides correctly through the real module load.
node - <<'JS'
const { choose } = require('/app/drone.js');
if (typeof choose !== 'function') { process.exit(1); }
if (choose({ grid: [[3,7,1],[8,0,4],[2,9,6]], row: 1, col: 1 }) !== 'south') { process.exit(1); }
if (choose({ grid: [[3,7,1],[8,0,4],[2,9,6]], row: 1, col: 1, visited: [[2,1]] }) !== 'west') { process.exit(1); }
if (choose({ row: 0, col: 0 }) !== 'hold') { process.exit(1); }
JS

# Produce the visible walkthrough deliverable with the batch driver.
node /app/simulate.js /app/scenario.json /app/walkthrough.json

echo "solve.sh done -> /app/drone.js, /app/simulate.js, /app/walkthrough.json"
