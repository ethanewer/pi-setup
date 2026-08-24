#!/usr/bin/env node
/*
 * tools/run.js — runner for the MIPS framebuffer binary.
 *
 * Node.js-based runner that:
 *   1. parses the ELF identification bytes and enforces the target ABI
 *      manifest from tools/abi.txt (MIPS, big-endian, ELF32, e_machine=8),
 *   2. executes the binary under the QEMU-user MIPS VM (qemu-mips),
 *   3. forwards the binary's stdout byte-for-byte to its own stdout
 *      (so `make run` can redirect it into out.dat),
 *   4. prints a SHA-256 of the emitted frame to stderr for quick diffing.
 *
 * Usage: node tools/run.js <elf-path>
 * Exit codes: 0 = ran OK; 3 = wrong endianness; 4 = not a MIPS ELF;
 *             other = qemu-mips exit status.
 */
'use strict';
const fs = require('fs');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const path = process.argv[2];
if (!path) { process.stderr.write('usage: node tools/run.js <elf>\n'); process.exit(2); }

const head = fs.readFileSync(path);
const eiClass = head[4], eiData = head[5];
const eMachine = head.readUInt16BE(18);

const err = (code, msg) => { process.stderr.write('run.js: ' + msg + '\n'); process.exit(code); };

if (eiClass !== 1) err(4, 'ABI check failed: EI_CLASS=' + eiClass + ' — expected 1 (ELF32). ' +
    'Target ABI is MIPS o32 (see tools/abi.txt).');
if (eiData !== 2) err(3, 'ABI check failed: EI_DATA=' + eiData + ' — expected 2 (big-endian). ' +
    'Your binary was built for the wrong byte order; check the toolchain prefix in the Makefile.');
if (eMachine !== 8) err(4, 'ABI check failed: e_machine=' + eMachine + ' — expected 8 (EM_MIPS). ' +
    'Your binary was not built for MIPS at all.');

process.stderr.write('run.js: ABI ok (MIPS, big-endian, ELF32); guest under qemu-mips.\n');
let out;
try {
  out = execFileSync('qemu-mips', [path], { stdio: ['ignore', 'pipe', 'inherit'] });
} catch (e) {
  process.stderr.write('run.js: qemu-mips failed: ' + (e.message || e) + '\n');
  process.exit(e.status ?? 1);
}
process.stdout.write(out);
process.stderr.write('run.js: guest exited 0; frame sha256=' +
  crypto.createHash('sha256').update(out).digest('hex') + '\n');