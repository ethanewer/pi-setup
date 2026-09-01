#!/usr/bin/env node
// Latchkey ops launcher (immutable lab input — do NOT modify).
//
// Boots the Latchkey stream engine at /app/bin/latch-engine and drives the
// framed session protocol against an independent reference implementation.
//
// Usage: node /app/launcher.mjs <session-file>
//   session file: first non-comment line is  seed=<int 0..4294967295>
//                 remaining non-comment lines are decimal request counts.
//
// Prints FRAME_OK <i> per request and SESSION_OK <count> on success (exit 0),
// or BOOT_FAIL / FRAME_FAIL <i> on failure (exit 1).
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

const ENGINE = '/app/bin/latch-engine';
const PROBE_BANNER = 'LATCH/1 READY';

function fail(msg) {
  console.error('BOOT_FAIL ' + msg);
  process.exit(1);
}

// ---- 1. discovery: the entrypoint must exist, right there, executable ----
try {
  fs.accessSync(ENGINE, fs.constants.X_OK);
} catch {
  fail('no executable engine at ' + ENGINE);
}

// ---- 2. boot probe: exact banner on stdout, exit 0 ------------------------
const probe = spawnSync(ENGINE, ['--probe'], { encoding: 'utf8', timeout: 10000 });
if (probe.error) fail('probe spawn error: ' + probe.error.message);
if (probe.status !== 0 || probe.stdout !== PROBE_BANNER + '\n') {
  fail('probe mismatch: status=' + probe.status +
       ' stdout=' + JSON.stringify(probe.stdout));
}

// ---- 3. parse the session file --------------------------------------------
const file = process.argv[2];
if (!file) fail('usage: launcher.mjs <session-file>');
let text;
try {
  text = fs.readFileSync(file, 'utf8');
} catch {
  fail('cannot read session file ' + file);
}
let seed = null;
const reqs = [];
for (const raw of String(text).split(/\r?\n/)) {
  const line = raw.trim();
  if (!line || line.startsWith('#')) continue;
  if (seed === null) {
    if (!line.startsWith('seed=')) fail('first line must be seed=<int>');
    seed = Number(line.slice(5));
    if (!Number.isInteger(seed) || seed < 0 || seed > 4294967295) {
      fail('bad seed value');
    }
    continue;
  }
  if (!/^[0-9]+$/.test(line)) fail('bad request line: ' + JSON.stringify(line));
  const n = Number(line);
  if (n > 1000000) fail('request too large');
  reqs.push(n);
}
if (seed === null) fail('session file has no seed line');

// ---- 4. reference keystream (must match the documented engine spec) -------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[i] = c >>> 0;
  }
  return t;
})();

function crc32(str) {
  let c = 0xffffffff;
  const bytes = Buffer.from(str, 'latin1');
  for (const b of bytes) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function referenceFrames(seedVal, requests) {
  let s = seedVal >>> 0;
  const frames = [];
  for (const n of requests) {
    let payload = '';
    for (let i = 0; i < n; i++) {
      s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
      payload += String.fromCharCode(97 + ((s >>> 7) % 26));
    }
    frames.push({ n, payload, crc: crc32(payload) });
  }
  return frames;
}

// ---- 5. drive one engine session ------------------------------------------
const input = reqs.map(String).join('\n') + '\n';
const run = spawnSync(ENGINE, ['--serve', String(seed)], {
  input,
  encoding: 'utf8',
  timeout: 60000,
  maxBuffer: 64 * 1024 * 1024,
});
if (run.error) fail('serve spawn error: ' + run.error.message);
if (run.status !== 0) {
  fail('engine exited ' + run.status + ': ' + String(run.stderr || '').slice(0, 200));
}

// ---- 6. frame-by-frame comparison -----------------------------------------
const frames = referenceFrames(seed, reqs);
let cursor = 0;
for (let i = 0; i < frames.length; i++) {
  const f = frames[i];
  const expect =
    'BEGIN ' + f.n + '\n' + f.payload + '\n' +
    'END ' + f.crc.toString(16).padStart(8, '0') + '\n';
  const got = run.stdout.slice(cursor, cursor + expect.length);
  if (got !== expect) {
    console.error('FRAME_FAIL ' + i +
      ' got=' + JSON.stringify(got.slice(0, 120)) +
      ' want=' + JSON.stringify(expect.slice(0, 120)));
    process.exit(1);
  }
  cursor += expect.length;
  console.log('FRAME_OK ' + i);
}
if (run.stdout.slice(cursor) !== '') {
  fail('trailing output after last frame: ' +
       JSON.stringify(run.stdout.slice(cursor, cursor + 120)));
}
console.log('SESSION_OK ' + frames.length);
