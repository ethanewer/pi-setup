'use strict';
// stanchion-compass verifier harness.
//
//   1. rebuilds the app via `npm run build` in /app,
//   2. parses the emitted chunk graph from dist/index.html (static-import BFS
//      from the entry) and asserts:
//        - initial-fetch byte budget (entry + static imports + inline script),
//        - chunk count, per-view lazy chunks with unique heavy-module markers,
//          dynamic-import references in the entry, no duplicated data modules,
//        - react/react-dom vendor code separated from the entry chunk,
//   3. boots the built bundle under jsdom, once per case (visible + hidden),
//      asserting the route chunk is actually fetched and executed and the
//      route interactions work.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');

const APP = process.env.SC_APP || '/app';
const PKG = path.join(APP, 'package.json');
const DIST_DIR = path.join(APP, 'dist');
const ASSETS = path.join(DIST_DIR, 'assets');
const BUDGET = 400000;
const MIN_CHUNKS = 5;
const MIN_TOTAL_JS = 200000;

// Unique token present in react-dom's production client bundle; it must NOT
// be in the entry chunk after vendor splitting.
const VENDOR_TOKEN = '__DOM_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE';

const VIEWS = {
  charts: { chunk: 'ChartsView', marker: 'sc_mk_9f31_charts', head: 'scm_9f31_charts' },
  reports: { chunk: 'ReportsView', marker: 'sc_mk_d20a_reports', head: 'scm_d20a_reports' },
  admin: { chunk: 'AdminView', marker: 'sc_mk_73b4_admin', head: 'scm_73b4_admin' },
};

const failures = [];
const fail = (m) => failures.push(m);

function jsChunks() {
  if (!fs.existsSync(ASSETS)) return [];
  return fs
    .readdirSync(ASSETS)
    .filter((f) => f.endsWith('.js'))
    .sort();
}

const filePath = (name) => path.join(ASSETS, name);

function staticImports(src) {
  const out = [];
  const re = /(?:from|import)\s*["']\s*([^"']+\.js)(?:\?[^"']*)?["']/g;
  let m;
  while ((m = re.exec(src)) !== null) out.push(m[1]);
  return out;
}

function baseName(spec) {
  // Strip leading ./  /  or assets/ prefixes and keep the file name.
  const s = spec.split('/').pop();
  return s;
}

function parseIndex() {
  const html = fs.readFileSync(path.join(DIST_DIR, 'index.html'), 'utf8');
  const scripts = [];
  const inline = [];
  const reScript = /<script[^>]+src=["']([^"']+\.js)(?:\?[^"']*)?["'][^>]*>/g;
  let m;
  while ((m = reScript.exec(html)) !== null) scripts.push(m[1]);
  const reInline = /<script[^>]*type=["']module["'][^>]*>([\s\S]*?)<\/script>/g;
  while ((m = reInline.exec(html)) !== null) {
    if (!/<script[^>]+src=/.test(m[0])) inline.push(m[1]);
  }
  return { scripts, inline };
}

function main() {
  // ---------- 0. rebuild ----------
  if (!fs.existsSync(PKG)) {
    fail('missing deliverable /app/package.json');
  } else {
    console.log('build: starting npm run build');
    try {
      execFileSync('npm', ['run', 'build'], { cwd: APP, stdio: ['ignore', 'pipe', 'pipe'], timeout: 420000 });
      console.log('build: ok');
    } catch (e) {
      const msg = (e.stderr || e.stdout || String(e)).toString();
      fail('npm run build failed: ' + msg.split('\n').slice(-10).join(' | '));
    }
  }

  if (!fs.existsSync(path.join(DIST_DIR, 'index.html'))) {
    fail('/app/dist/index.html missing (build produced no output)');
  }
  const chunks = jsChunks();
  if (chunks.length === 0) fail('/app/dist/assets contains no JS chunks');
  console.log('chunks:', chunks.length, chunks.join(', '));

  // ---------- 1. entry + static-import reachability ----------
  const { scripts, inline } = parseIndex();
  const seeds = [...new Set(scripts.map(baseName))].filter((f) => fs.existsSync(filePath(f)));
  if (seeds.length === 0) fail('could not locate the entry chunk from dist/index.html scripts');

  const read = (f) => fs.readFileSync(filePath(f), 'utf8');
  const queued = [...seeds];
  const seen = new Set(seeds);
  while (queued.length) {
    const f = queued.pop();
    for (const dep of staticImports(read(f))) {
      const b = baseName(dep);
      if (b.endsWith('.js') && fs.existsSync(filePath(b)) && !seen.has(b)) {
        seen.add(b);
        queued.push(b);
      }
    }
  }
  const inlineText = inline.join('\n');
  const initialBytes =
    Buffer.byteLength(inlineText, 'utf8') +
    [...seen].reduce((acc, f) => acc + fs.statSync(filePath(f)).size, 0);

  console.log('initial fetch reachable chunks:', [...seen].join(', '));
  console.log('initial fetch bytes:', initialBytes);

  // ---------- 2. static gate A: byte budget ----------
  if (initialBytes > BUDGET) {
    fail('initial fetch is ' + initialBytes + ' bytes; budget is ' + BUDGET);
  } else {
    console.log('budget: ok (' + initialBytes + ' <= ' + BUDGET + ')');
  }

  // ---------- 3. static gate B: chunk count ----------
  if (chunks.length < MIN_CHUNKS) {
    fail('only ' + chunks.length + ' JS chunks in /app/dist/assets; need at least ' + MIN_CHUNKS);
  }

  // ---------- 4. static gate C: total shipped JS floor ----------
  const totalJs = chunks.reduce((acc, f) => acc + fs.statSync(filePath(f)).size, 0);
  if (totalJs < MIN_TOTAL_JS) {
    fail('total shipped JS is only ' + totalJs + ' bytes; app looks gutted');
  }

  // ---------- 5. static gate D: per-view lazy chunks + markers ----------
  const entryContent = inlineText + [...seeds].map(read).join('\n');
  for (const key of Object.keys(VIEWS)) {
    const v = VIEWS[key];
    const viewFiles = chunks.filter((f) => f.startsWith(v.chunk + '-') && f.endsWith('.js'));
    if (viewFiles.length !== 1) {
      fail(
        key + ': expected exactly one chunk named ' + v.chunk + '-*.js, found ' +
          (viewFiles.length ? viewFiles.join(',') : 'none')
      );
      continue;
    }
    const vf = viewFiles[0];
    if (seeds.includes(vf)) fail(key + ': view chunk ' + vf + ' is part of the initial fetch, not lazy');
    const content = read(vf);
    if (!content.includes(v.marker)) fail(key + ': chunk ' + vf + ' does not contain its data module marker');
    if (!content.includes(v.head)) fail(key + ': chunk ' + vf + ' does not contain its route head constant');
    // marker must appear in exactly that one chunk
    for (const other of chunks) {
      if (other !== vf && read(other).includes(v.marker)) {
        fail(key + ': marker duplicated in chunk ' + other);
      }
    }
    if (!entryContent.includes(v.chunk + '-')) {
      fail(key + ': entry does not dynamically reference the ' + v.chunk + ' chunk (' + v.chunk + '-<hash>.js)');
    }
    if (entryContent.includes(v.marker)) fail(key + ': data module marker leaked into the entry chunk');
    console.log(key + ': lazy chunk ok (' + vf + ')');
  }

  // ---------- 6. static gate E: vendor separation ----------
  const vendorHits = chunks.filter((f) => read(f).includes(VENDOR_TOKEN));
  if (entryContent.includes(VENDOR_TOKEN)) {
    fail('react-dom vendors code is inside the entry chunk (no vendor split)');
  } else if (vendorHits.length === 0) {
    fail('react-dom vendor code not found in any emitted chunk');
  } else {
    console.log('vendor: react-dom code found only outside the entry (' + vendorHits.join(', ') + ')');
  }

  // ---------- 7. runtime gate: boot every case (visible + hidden) ----------
  const entryFile = filePath(seeds[0]);
  const cases = process.argv.slice(2).filter((f) => f.endsWith('.json'));
  if (cases.length === 0) fail('no case fixtures supplied to the verifier');
  for (const c of cases) {
    const label = (() => {
      try {
        return JSON.parse(fs.readFileSync(c, 'utf8')).label || c;
      } catch {
        return c;
      }
    })();
    const r = spawnSync(process.execPath, [path.join(__dirname, 'boot.cjs'), entryFile, c], {
      encoding: 'utf8',
      timeout: 60000,
    });
    if (r.status === 0) {
      console.log('boot ' + label + ': ok');
    } else {
      fail('boot ' + label + ' FAILED: ' + (r.stdout || '').trim() + ' ' + (r.stderr || '').trim());
    }
  }

  // ---------- report ----------
  if (failures.length > 0) {
    console.error('stanchion-compass VERIFIER FAILURES:');
    for (const f of failures) console.error('  - ' + f);
    return 1;
  }
  console.log('stanchion-compass: ALL CHECKS PASSED');
  return 0;
}

process.exit(main());