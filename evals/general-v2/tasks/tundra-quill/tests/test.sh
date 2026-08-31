#!/bin/bash
# Verifier for tundra-quill: loads the deliverable /app/pilot.js with require(),
# enforces the pure-JS source constraints (no require(), no import statement,
# no class declaration) and EXECUTES exports.step on every hidden case under
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

node - <<'JS'
const fs = require('fs');
const path = require('path');

const FILE = '/app/pilot.js';
const failures = [];

if (!fs.existsSync(FILE)) {
    failures.push('missing /app/pilot.js');
} else {
    const src = fs.readFileSync(FILE, 'utf8');
    if (/require\s*\(/.test(src)) failures.push('source calls require()');
    if (/(^|\n)\s*import[\s"']/.test(src)) failures.push('source uses an import statement');
    if (/\bclass\s+[A-Za-z_$]/.test(src)) failures.push('source declares a class');

    let mod = null;
    try {
        mod = require(FILE);
    } catch (e) {
        failures.push('failed to load /app/pilot.js: ' + e.message);
    }
    if (mod) {
        if (!mod || typeof mod.step !== 'function') {
            failures.push('exports.step is not a function');
        } else {
            const hidden = '/tests/hidden';
            const cases = fs.existsSync(hidden) ? fs.readdirSync(hidden).sort() : [];
            if (!cases.length) failures.push('no hidden cases present');
            for (const c of cases) {
                const base = path.join(hidden, c);
                const cellPath = path.join(base, 'cell.json');
                const expPath = path.join(base, 'expected.json');
                if (!fs.existsSync(cellPath) || !fs.existsSync(expPath)) {
                    failures.push('hidden case \'' + c + '\' malformed');
                    continue;
                }
                try {
                    const cell = JSON.parse(fs.readFileSync(cellPath, 'utf8'));
                    const want = JSON.parse(fs.readFileSync(expPath, 'utf8'));
                    const got = mod.step(cell);
                    if (got !== want) {
                        failures.push('hidden case \'' + c + '\': got ' +
                            JSON.stringify(got) + ', want ' + JSON.stringify(want));
                    }
                } catch (e) {
                    failures.push('hidden case \'' + c + '\' threw: ' + e.message);
                }
            }
        }
    }
}

console.log('verify failures:', failures);
process.exit(failures.length ? 1 : 0);
JS

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
