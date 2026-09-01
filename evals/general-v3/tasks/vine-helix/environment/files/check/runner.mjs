#!/usr/bin/env node
/**
 * vine-helix: bundled trial checker (Node).
 *
 *   node runner.mjs [trials] [solution] [out]
 *
 *   trials    JSON: array of { id, cells } layouts
 *   solution  JSON: object mapping layout id -> submitted turn count
 *   out       results JSON written (default /app/results/results.json)
 *
 * This runnable re-derives the *oracle* turn count for every layout from the
 * spec alone:   turns = 2*cells + 1
 * and grades the submitted answer against that oracle. It writes a results
 * report (per-trial status + a summary with the passing count) that the floor
 * reads for self-verification, and exits non-zero if any trial is FAIL.
 */
import fs from 'fs';
import path from 'path';

const BASE = '/app/check';
const cli = process.argv.slice(2);
const trialsArg  = cli[0] || path.join(BASE, 'trials.json');
const solArg     = cli[1] || path.join(BASE, 'solution.json');
const outArg     = cli[2] || '/app/results/results.json';

const oracle = (cells) => 2 * cells + 1;

let trials = [];
try {
  const parsed = JSON.parse(fs.readFileSync(trialsArg, 'utf8'));
  if (Array.isArray(parsed)) trials = parsed;
} catch (e) { /* unreadable -> empty, all failed */ }

let solution = {};
try { solution = JSON.parse(fs.readFileSync(solArg, 'utf8')); } catch (e) {}

const graded = [];
let passed = 0, failed = 0;
for (const t of trials) {
  const id = String(t.id);
  const cells = t.cells;
  const expected = Number.isInteger(cells) && cells >= 0 ? oracle(cells) : 'unsupported-cells';
  const got = solution[id];
  const ok = Number.isInteger(expected) && Number.isInteger(got) && got === expected;
  if (ok) passed += 1; else failed += 1;
  graded.push({ id, cells, expected, got: (got === undefined ? null : got), status: ok ? 'PASS' : 'FAIL' });
}

const summary = { total: trials.length, passed, failed };
const results = { generated_at: new Date().toISOString(), summary, trials: graded };
fs.mkdirSync(path.dirname(outArg), { recursive: true });
fs.writeFileSync(outArg, JSON.stringify(results, null, 2));

console.log(`trials=${summary.total} passed=${summary.passed} failed=${summary.failed}`);
process.exit(summary.total > 0 && summary.failed === 0 ? 0 : 1);