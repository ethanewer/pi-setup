'use strict';

// cistern-ferry reproducer for the reported attribute-casing bug in Prettier.
//
// A user reports that formatting an HTML file normalizes attribute names to
// lowercase on some well-known tags but not others: <div CLASS="..."> is
// rewritten to <div class="...">, yet <span CLASS="..."> keeps its uppercase
// attribute name on the same input. Formatting the file below with the real
// Prettier CLI used to reproduce this:
//
//   node bin/prettier.js b.html
//
// Run this script with the prettier checkout at /app/src:
//
//   node /app/reproduce.js
//
// It exits 0 when attribute names on both tags are lowercased consistently,
// and exits 1 (printing the observed output) while the bug is present.

const { execFileSync } = require('node:child_process');
const { writeFileSync, mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');

const INPUT =
  '<span CLASS="should print as lowercase">text</span>\n' +
  '<div CLASS="should print as lowercase">text</div>\n';

const dir = mkdtempSync(join(tmpdir(), 'cistern-ferry-'));
const file = join(dir, 'b.html');
writeFileSync(file, INPUT);

let stdout;
try {
  stdout = execFileSync(
    process.execPath,
    [join('/app/src', 'bin', 'prettier.js'), file],
    { encoding: 'utf8', cwd: '/app/src', stdio: ['ignore', 'pipe', 'inherit'] },
  );
} catch (err) {
  console.error('prettier CLI failed:', err.message);
  process.exit(1);
}

console.log('--- formatted output (node bin/prettier.js b.html) ---');
process.stdout.write(stdout);

const spanOk = stdout.includes(
  '<span class="should print as lowercase">text</span>',
);
const divOk = stdout.includes(
  '<div class="should print as lowercase">text</div>',
);
const anyUppercase = /CLASS/.test(stdout);

if (spanOk && divOk && !anyUppercase) {
  console.log('OK: attribute names on both <span> and <div> lowercased consistently');
  process.exit(0);
}

console.log(
  'BUG REPRODUCED: attribute names are not normalized consistently - ' +
    'expected <div class=...> and <span class=...> (as in a correctly ' +
    'formatted file); one or both still carry an uppercase attribute name.',
);
process.exit(1);