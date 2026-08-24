#!/bin/bash
# Oracle solution: a correct tiny VM in Node.js.
set -euo pipefail

cat > /app/vm.js <<'JS'
const fs = require('fs');

const file = process.argv[2];
const data = fs.readFileSync(file);
const reg = new Array(8).fill(0);
const out = [];

for (let off = 0; off < data.length; off += 12) {
  const op = data.readUInt32LE(off);
  const rA = data.readUInt32LE(off + 4);
  const rB = data.readUInt32LE(off + 8);
  if (op === 1) {            // LOADI
    reg[rA] = rB;
  } else if (op === 2) {     // ADD
    reg[rA] = (reg[rA] + reg[rB]) >>> 0;
  } else if (op === 3) {     // SUB
    reg[rA] = (reg[rA] - reg[rB]) >>> 0;
  } else if (op === 4) {     // PRINT
    out.push(String(reg[rA]));
  } else if (op === 5) {     // MOV
    reg[rA] = reg[rB];
  }
}

fs.writeFileSync('/app/output.txt', out.join('\n') + '\n');
JS

node /app/vm.js /app/program.bin
