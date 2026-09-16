/*
 * Verify the stanchion-bell deliverable: /app/src (the remediated React app).
 *
 *   1. the shipped app is present and its npm toolchain is intact
 *   2. the hidden page cases from /tests/hidden are staged into
 *      /app/.hidden-tests (tree preserved so relative imports hold)
 *   3. a known-good vitest configuration is written over the app's local
 *      one (the agent may have edited it; it is not part of the deliverable)
 *   4. vitest runs the visible suite plus the staged hidden pages under
 *      jsdom; every page must pass axe-core (no moderate+ violations) and
 *      the targeted skip-link / focus-order / live-region / colour-state /
 *      label / heading checks in tools/a11y.mjs (verifier copy)
 *
 * Exit code 0 only when every page passes. Readable failures go to stdout.
 */
import { spawnSync } from 'node:child_process';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';

const APP = '/app';
const SRC = '/app/src/';
const HIDDEN = '/tests/hidden';
const STAGED = '/app/.hidden-tests';

const VITEST_CONFIG = `import { defineConfig } from 'vitest/config';
// Overwritten by the stanchion-bell verifier so the agent's edits to the
// local config cannot touch the checks that run at grading time.
export default defineConfig({
  esbuild: { jsx: 'automatic' },
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['visible/**/*.test.jsx', '.hidden-tests/**/*.test.jsx'],
    setupFiles: ['./vitest.setup.mjs'],
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } },
    testTimeout: 30000,
    hookTimeout: 60000,
  },
});
`;

const VITEST_SETUP = `import { afterEach } from 'vitest';
import { cleanup } from '@testing-library/react';
// Guarantee a clean document between tests (verifier-owned copy).
afterEach(() => {
  cleanup();
});
`;

const failures = [];
function fail(msg) {
  failures.push(msg);
}

// ---- 1) deliverables -------------------------------------------------------
if (!existsSync(path.join(APP, 'src', 'App.jsx'))) {
  fail('missing /app/src/App.jsx (the root component)');
}
if (!existsSync(path.join(APP, 'node_modules', 'vitest', 'vitest.mjs'))) {
  fail('missing /app/node_modules (npm install did not run at build time?)');
}
if (!existsSync(path.join(APP, 'package.json'))) {
  fail('missing /app/package.json');
}

// ---- 2) stage the hidden cases, tree preserved ----------------------------
rmSync(STAGED, { recursive: true, force: true });
mkdirSync(STAGED, { recursive: true });

function copyTree(from, to) {
  mkdirSync(to, { recursive: true });
  for (const entry of readdirSync(from)) {
    const full = path.join(from, entry);
    const dst = path.join(to, entry);
    if (statSync(full).isDirectory()) {
      copyTree(full, dst);
    } else {
      copyFileSync(full, dst);
    }
  }
}

let cases = 0;
for (const entry of readdirSync(HIDDEN)) {
  const full = path.join(HIDDEN, entry);
  if (!statSync(full).isDirectory()) continue;
  if (entry.startsWith('_')) continue; // support modules, not page cases
  cases += 1;
  copyTree(full, path.join(STAGED, entry));
}
copyTree(path.join(HIDDEN, '_support'), path.join(STAGED, '_support'));
if (cases < 3) {
  fail(`expected >= 3 hidden page cases under ${HIDDEN}, found ${cases}`);
}

// ---- 3) write the known-good config ----------------------------------------
writeFileSync(path.join(APP, 'vitest.config.mjs'), VITEST_CONFIG);
writeFileSync(path.join(APP, 'vitest.setup.mjs'), VITEST_SETUP);

// ---- 4) run the whole suite (visible + hidden) -------------------------------
const vitestBin = path.join(APP, 'node_modules', 'vitest', 'vitest.mjs');
const r = spawnSync(process.execPath, [vitestBin, 'run'], {
  cwd: APP,
  encoding: 'utf8',
  timeout: 9 * 60 * 1000,
  env: { ...process.env, CI: 'true' },
});
process.stdout.write(r.stdout ?? '');
process.stderr.write(r.stderr ?? '');
if (r.status !== 0) {
  fail(`vitest suite failed (exit ${r.status}${r.error ? `: ${r.error.message}` : ''})`);
}

// ---- verdict -----------------------------------------------------------------
console.log('');
if (failures.length > 0) {
  console.log('stanchion-bell verify FAILURES:');
  for (const f of failures) console.log(`  - ${f}`);
  process.exit(1);
}
console.log('stanchion-bell verify: ALL PASS');
console.log(`  hidden page cases staged: ${cases}`);
console.log(`  suites: visible + ${cases} hidden pages under jsdom/axe`);
process.exit(0);