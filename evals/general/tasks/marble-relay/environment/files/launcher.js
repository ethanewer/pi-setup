#!/usr/bin/env node
'use strict';
/*
 * marble-relay frame launcher (shipped, immutable).
 *
 * Reads the agent-authored manifest /app/relay.json, whose "entry" field must
 * be exactly "/app/bin/relay", spawns it, and speaks the documented
 * length-prefixed JSON frame protocol on the child's stdio:
 *
 *   frame := 4-byte big-endian unsigned length, then that many UTF-8 JSON bytes
 *
 * Boot handshake: launcher sends {"type":"hello","proto":1}; the relay must
 * answer {"type":"ready","proto":1} within 5 seconds -> "BOOT_OK".
 * Then each query from the case file is sent; the relay's reply frame must
 * deep-equal the expected frame -> "FRAME_OK <i>" / "FRAME_FAIL <i> ...".
 * Finally "ALL_OK" (exit 0) or "ALL_FAIL" (exit 1); any boot problem prints
 * "BOOT_FAIL <reason>" and exits 3.
 */
const fs = require('fs');
const { spawn } = require('child_process');

const MANIFEST = '/app/relay.json';
const ENTRY = '/app/bin/relay';

function bootFail(reason) {
  process.stdout.write('BOOT_FAIL ' + reason + '\n');
  process.exit(3);
}

// ---- manifest / entrypoint discovery ----------------------------------- //
let raw = null;
try { raw = fs.readFileSync(MANIFEST, 'utf8'); }
catch (e) { bootFail('manifest unreadable: ' + e.message); }

let manifest = null;
try { manifest = JSON.parse(raw); }
catch (e) { bootFail('manifest is not valid JSON'); }

if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) {
  bootFail('manifest must be a JSON object');
}
if (manifest.entry !== ENTRY) {
  bootFail('manifest.entry is ' + JSON.stringify(manifest.entry) + ', want ' + JSON.stringify(ENTRY));
}
let st = null;
try { st = fs.statSync(ENTRY); }
catch (e) { bootFail('entrypoint not found: ' + ENTRY); }
if (!st.isFile()) bootFail('entrypoint is not a regular file: ' + ENTRY);

// ---- case file ---------------------------------------------------------- //
const caseFile = process.argv[2];
if (!caseFile) bootFail('usage: node launcher.js <case.json>');
let doc = null;
try { doc = JSON.parse(fs.readFileSync(caseFile, 'utf8')); }
catch (e) { bootFail('case file unreadable: ' + e.message); }
if (!doc || !Array.isArray(doc.queries)) bootFail('case file lacks a queries array');

// ---- spawn the relay ----------------------------------------------------- //
let child = null;
try {
  child = spawn(ENTRY, [], { stdio: ['pipe', 'pipe', 'pipe'] });
} catch (e) { bootFail('spawn failed: ' + e.message); }
child.on('error', (e) => bootFail('spawn failed: ' + e.message));
child.stdin.on('error', () => {});
child.stderr.pipe(process.stderr);

// ---- frame pump ---------------------------------------------------------- //
let buf = Buffer.alloc(0);
const frameQueue = [];
let frameErr = null;
const waiters = [];

function pump() {
  while (buf.length >= 4) {
    const len = buf.readUInt32BE(0);
    if (len > (1 << 22)) { frameErr = new Error('frame too large'); break; }
    if (buf.length < 4 + len) break;
    const payload = buf.slice(4, 4 + len).toString('utf8');
    buf = buf.slice(4 + len);
    let obj = null;
    try { obj = JSON.parse(payload); }
    catch (e) { obj = { __badjson: payload }; }
    frameQueue.push(obj);
  }
  while (waiters.length && (frameQueue.length || frameErr)) {
    const w = waiters.shift();
    if (frameQueue.length) w.resolve(frameQueue.shift());
    else w.reject(frameErr);
  }
}

child.stdout.on('data', (d) => { buf = Buffer.concat([buf, d]); pump(); });
child.stdout.on('end', () => { if (!frameErr) frameErr = new Error('relay closed stdout'); pump(); });

function nextFrame(timeoutMs) {
  return new Promise((resolve, reject) => {
    if (frameQueue.length) return resolve(frameQueue.shift());
    if (frameErr) return reject(frameErr);
    waiters.push({ resolve, reject });
    const t = setTimeout(() => reject(new Error('timeout')), timeoutMs);
    if (t && typeof t.unref === 'function') t.unref();
  });
}

function send(obj) {
  const payload = Buffer.from(JSON.stringify(obj), 'utf8');
  const head = Buffer.alloc(4);
  head.writeUInt32BE(payload.length, 0);
  child.stdin.write(Buffer.concat([head, payload]));
}

// ---- deep equality (key-order-insensitive, exact values) ---------------- //
function canon(v) {
  if (Array.isArray(v)) return v.map(canon);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) o[k] = canon(v[k]);
    return o;
  }
  return v;
}
function deepEq(a, b) {
  return JSON.stringify(canon(a)) === JSON.stringify(canon(b));
}

// ---- main ---------------------------------------------------------------- //
(async () => {
  send({ type: 'hello', proto: 1 });
  let ready = null;
  try { ready = await nextFrame(5000); }
  catch (e) { bootFail('boot handshake: ' + e.message); }
  if (!deepEq(ready, { type: 'ready', proto: 1 })) {
    bootFail('boot handshake: unexpected frame ' + JSON.stringify(ready));
  }
  process.stdout.write('BOOT_OK\n');

  let fails = 0;
  for (let i = 0; i < doc.queries.length; i++) {
    const q = doc.queries[i];
    if (!q || typeof q !== 'object' || !('send' in q) || !('expect' in q)) {
      process.stdout.write('FRAME_FAIL ' + i + ' malformed query entry\n');
      fails++;
      continue;
    }
    send(q.send);
    let got = null;
    try { got = await nextFrame(5000); }
    catch (e) {
      process.stdout.write('FRAME_FAIL ' + i + ' ' + e.message + '\n');
      fails++;
      continue;
    }
    if (!deepEq(got, q.expect)) {
      process.stdout.write('FRAME_FAIL ' + i + ' mismatch got=' + JSON.stringify(got) +
        ' want=' + JSON.stringify(q.expect) + '\n');
      fails++;
    } else {
      process.stdout.write('FRAME_OK ' + i + '\n');
    }
  }

  try { child.kill('SIGKILL'); } catch (e) { /* already gone */ }
  if (fails > 0) {
    process.stdout.write('ALL_FAIL\n');
    process.exit(1);
  }
  process.stdout.write('ALL_OK\n');
  process.exit(0);
})().catch((e) => bootFail('launcher error: ' + (e && e.message)));
