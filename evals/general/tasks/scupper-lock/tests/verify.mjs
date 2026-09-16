/*
 * Verify the scupper-lock deliverable: /app/DataTable.tsx (the React 18 data
 * table component) and /app/DataTable.md (its API reference).
 *
 * Steps:
 *   1. the documented prop surface must be present in /app/DataTable.md
 *   2. the hidden fixtures are staged into /app/.hidden-tests and the whole
 *      vitest suite (visible + hidden, jsdom + @testing-library/react) runs
 *   3. two hidden consumer files are strict type-checked against the
 *      deliverable with `tsc`
 *
 * Exit code 0 only when every step passes. Readable failures go to stdout.
 */
import { spawnSync } from 'node:child_process';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';

const APP = '/app';
const DELIVERABLE = '/app/DataTable.tsx';
const DOC = '/app/DataTable.md';
const HIDDEN = '/tests/hidden';

const failures = [];
function fail(msg) {
  failures.push(msg);
}

// ---- 1) deliverables ------------------------------------------------------
if (!existsSync(DELIVERABLE)) {
  fail(`missing deliverable ${DELIVERABLE}`);
}
if (!existsSync(DOC)) {
  fail(`missing deliverable ${DOC}`);
}

if (existsSync(DOC)) {
  const text = readFileSync(DOC, 'utf8');
  const tokens = [
    'DataTable',
    'DataTableProps',
    'ColumnDef',
    'SortState',
    'SortDirection',
    'data',
    'columns',
    'getRowId',
    'ariaLabel',
    'className',
    'getRowClassName',
    'selectionMode',
    'selectedIds',
    'defaultSelectedIds',
    'onSelectionChange',
    'sortable',
    'defaultSort',
    'onSortChange',
    'searchable',
    'defaultFilter',
    'filterText',
    'onFilterChange',
    'navigable',
  ];
  const missing = tokens.filter((t) => !text.includes(t));
  if (missing.length > 0) {
    fail(`DataTable.md does not document these required API identifiers: ${missing.join(', ')}`);
  }
  if (text.trim().length < 400) {
    fail('DataTable.md is too short to be a real API reference');
  }
  if (!/README|reference|API|props/i.test(text)) {
    fail('DataTable.md does not look like a prop reference document');
  }
}

// ---- 2. stage the hidden fixtures ----------------------------------------
const stagedTests = '/app/.hidden-tests';
const stagedTypes = '/app/.hidden-types';
rmSync(stagedTests, { recursive: true, force: true });
rmSync(stagedTypes, { recursive: true, force: true });
mkdirSync(stagedTests, { recursive: true });
mkdirSync(stagedTypes, { recursive: true });

let testFiles = 0;
let consumerFiles = 0;
for (const entry of readdirSync(HIDDEN)) {
  const dir = path.join(HIDDEN, entry);
  if (!statSync(dir).isDirectory()) continue;
  for (const file of readdirSync(dir)) {
    const full = path.join(dir, file);
    if (!statSync(full).isFile()) continue;
    if (file.endsWith('.test.tsx')) {
      copyFileSync(full, path.join(stagedTests, `${entry}-${file}`));
      testFiles += 1;
    } else if (file.endsWith('.tsx') || file.endsWith('.ts')) {
      copyFileSync(full, path.join(stagedTypes, `${entry}-${file}`));
      consumerFiles += 1;
    }
  }
}
if (testFiles < 4) fail(`expected >= 4 hidden test files, found ${testFiles}`);
if (consumerFiles < 2) fail(`expected >= 2 hidden consumer files, found ${consumerFiles}`);

function run(cmd, args) {
  return spawnSync(cmd, args, {
    cwd: APP,
    encoding: 'utf8',
    timeout: 5 * 60 * 1000,
    env: { ...process.env, CI: 'true' },
  });
}

// ---- 3. vitest suite (visible + hidden) -----------------------------------
const vitestBin = path.join(APP, 'node_modules', 'vitest', 'vitest.mjs');
const vitestArgs = [
  'run',
  '--config',
  path.join(APP, 'vitest.config.ts'),
  path.join(APP, 'visible'),
  stagedTests,
];
let r = run(process.execPath, [vitestBin, ...vitestArgs]);
process.stdout.write(r.stdout ?? '');
process.stderr.write(r.stderr ?? '');
if (r.status !== 0) {
  fail(`vitest suite failed (exit ${r.status}${r.error ? `: ${r.error.message}` : ''})`);
}

// ---- 4. strict type-check of hidden consumers against the deliverable -----
const checkTsconfig = path.join(APP, '.check-tsconfig.json');
writeFileSync(
  checkTsconfig,
  JSON.stringify(
    {
      extends: path.join(APP, 'tsconfig.json'),
      include: [`${stagedTypes}/**/*.tsx`, DELIVERABLE],
      compilerOptions: { noEmit: true },
    },
    null,
    2,
  ),
);
const tscBin = path.join(APP, 'node_modules', '.bin', 'tsc');
r = spawnSync(tscBin, ['-p', checkTsconfig], {
  cwd: APP,
  encoding: 'utf8',
  timeout: 5 * 60 * 1000,
});
process.stdout.write(r.stdout ?? '');
process.stderr.write(r.stderr ?? '');
if (r.status !== 0) {
  fail(`hidden consumer type-check failed (exit ${r.status})`);
}

// ---- verdict ---------------------------------------------------------------
console.log('');
if (failures.length > 0) {
  console.log('scupper-lock verify FAILURES:');
  for (const f of failures) console.log(`  - ${f}`);
  process.exit(1);
}
console.log('scupper-lock verify: ALL PASS');
console.log(`  hidden test files staged: ${testFiles}`);
console.log(`  hidden consumer files type-checked: ${consumerFiles}`);
console.log(`  vitest entries: ${(r.stdout ?? '').match(/Test Files\s+\d+/)?.[0] ?? 'n/a'}`);
process.exit(0);