#!/usr/bin/env node
// pumice-core: a MIPS32 (big-endian) ELF interpreter.
//   node vm.js <elf-file>
// Guest stdout/stderr flow through; exit status = guest exit status.
'use strict';
const fs = require('fs');

const MEM_SIZE = 0x04000000;      // 64 MiB flat guest memory
const SP_INIT = 0x03FFF000;
const STEP_LIMIT = 50000000;

function die(msg, code) {
  process.stderr.write('pumice: ' + msg + '\n');
  process.exit(code);
}

let path = process.argv[2];
if (!path) die('usage: node vm.js <elf-file>', 1);
let buf;
try {
  buf = fs.readFileSync(path);
} catch (e) {
  die('cannot read ' + path, 1);
}

// ---- ELF loading (ELF32, big-endian, EM_MIPS) ----
if (buf.length < 52 || buf[0] !== 0x7f || buf[1] !== 0x45 || buf[2] !== 0x4c || buf[3] !== 0x46)
  die('not an ELF file', 1);
if (buf[4] !== 1) die('not ELFCLASS32', 1);
if (buf[5] !== 2) die('not big-endian (ei_data != 2)', 1);
const e_type = buf.readUInt16BE(16);
const e_machine = buf.readUInt16BE(18);
const entry = buf.readUInt32BE(24);
const e_phoff = buf.readUInt32BE(28);
const e_phentsize = buf.readUInt16BE(42);
const e_phnum = buf.readUInt16BE(44);
if (e_machine !== 8) die('not a MIPS ELF (e_machine=' + e_machine + ')', 1);

const mem = new Uint8Array(MEM_SIZE);
for (let i = 0; i < e_phnum; i++) {
  const p = e_phoff + i * e_phentsize;
  const p_type = buf.readUInt32BE(p);
  if (p_type !== 1) continue;              // PT_LOAD only
  const p_offset = buf.readUInt32BE(p + 4);
  const p_vaddr = buf.readUInt32BE(p + 8);
  const p_filesz = buf.readUInt32BE(p + 16);
  const p_memsz = buf.readUInt32BE(p + 20);
  if (p_vaddr + p_memsz > MEM_SIZE) die('PT_LOAD segment exceeds guest memory', 7);
  for (let j = 0; j < p_filesz; j++) mem[p_vaddr + j] = buf[p_offset + j];
  for (let j = p_filesz; j < p_memsz; j++) mem[p_vaddr + j] = 0;   // bss zero-fill
}

// ---- machine state ----
const r = new Int32Array(32);
r[29] = SP_INIT;   // $sp
const hi = { v: 0 }, lo = { v: 0 };
let pc = entry >>> 0;
let npc = (entry + 4) >>> 0;
let steps = 0;

function s32(x) { return x | 0; }
function u32(x) { return x >>> 0; }

function chk(addr, size, what) {
  if (addr + size > MEM_SIZE) die(what + ' out of range at 0x' + addr.toString(16), 7);
  return addr;
}

function algn(a, n) { if (a % n !== 0) die('unaligned ' + n + '-byte access at 0x' + a.toString(16), 7); return a; }

function fetch32(a) {
  chk(a, 4, 'instruction fetch');
  return (mem[a] << 24) | (mem[a + 1] << 16) | (mem[a + 2] << 8) | mem[a + 3];
}
function read8(a) { chk(a, 1, 'load'); return mem[a]; }
function read16(a) { chk(a, 2, 'load'); return (mem[a] << 8) | mem[a + 1]; }
function read32(a) { chk(a, 4, 'load'); return fetch32(a); }
function write8(a, v) { chk(a, 1, 'store'); mem[a] = v & 0xFF; }
function write16(a, v) { chk(a, 2, 'store'); mem[a] = (v >>> 8) & 0xFF; mem[a + 1] = v & 0xFF; }
function write32(a, v) { chk(a, 4, 'store'); v = s32(v); mem[a] = (v >>> 24) & 0xFF; mem[a + 1] = (v >>> 16) & 0xFF; mem[a + 2] = (v >>> 8) & 0xFF; mem[a + 3] = v & 0xFF; }

function printInt(v) { process.stdout.write(String(s32(v)) + '\n'); }
function printStr(a, n) {
  chk(a, n, 'string');
  process.stdout.write(Buffer.from(mem.slice(a, a + n)).toString('latin1'));
}

function syscall() {
  const v0 = r[2], a0 = r[4];
  if (v0 === 343) { printInt(a0); }
  else if (v0 === 344) { printStr(u32(a0), s32(r[5])); }
  else if (v0 === 93) { process.exit(a0 & 0xFF); }
  else die('unknown syscall ' + s32(v0), 8);
}

function setLoHi(v) { lo.v = s32(v); }

function execute(inst) {
  const op = (inst >>> 26) & 0x3F;
  const rs = (inst >>> 21) & 0x1F;
  const rt = (inst >>> 16) & 0x1F;
  const rd = (inst >>> 11) & 0x1F;
  const sh = (inst >>> 6) & 0x1F;
  const funct = inst & 0x3F;
  const imm = inst & 0xFFFF;
  const simm = (imm << 16) >> 16;

  if (op === 0x00) {
    switch (funct) {
      case 0x00: r[rd] = s32(r[rt] << sh); break;             // sll
      case 0x02: r[rd] = s32(r[rt] >>> sh); break;            // srl
      case 0x03: r[rd] = s32(r[rt] >> sh); break;             // sra
      case 0x04: r[rd] = s32(r[rt] << (r[rs] & 31)); break;   // sllv
      case 0x06: r[rd] = s32(r[rt] >>> (r[rs] & 31)); break;  // srlv
      case 0x07: r[rd] = s32(r[rt] >> (r[rs] & 31)); break;   // srav
      case 0x08: return r[rs] >>> 0;                          // jr
      case 0x09: r[rd] = s32(pc + 8); return r[rs] >>> 0;     // jalr
      case 0x0C: syscall(); break;
      case 0x10: r[rd] = hi.v; break;                         // mfhi
      case 0x11: hi.v = r[rs]; break;                         // mthi
      case 0x12: r[rd] = lo.v; break;                         // mflo
      case 0x13: lo.v = r[rs]; break;                         // mtlo
      case 0x18: { const p = BigInt(s32(r[rs])) * BigInt(s32(r[rt]));   // mult
                   lo.v = s32(Number(BigInt.asIntN(64, p) & 0xFFFFFFFFn));
                   hi.v = s32(Number((BigInt.asIntN(64, p) >> 32n) & 0xFFFFFFFFn)); break; }
      case 0x19: { const p = BigInt(u32(r[rs])) * BigInt(u32(r[rt]));   // multu
                   lo.v = s32(Number(p & 0xFFFFFFFFn));
                   hi.v = s32(Number((p >> 32n) & 0xFFFFFFFFn)); break; }
      case 0x1A: { const a = s32(r[rs]), b = s32(r[rt]);                // div
                   if (b !== 0) { lo.v = s32(Math.trunc(a / b)); hi.v = s32(a % b); } break; }
      case 0x1B: { const a = u32(r[rs]), b = u32(r[rt]);                // divu
                   if (b !== 0) { lo.v = s32(Math.floor(a / b)); hi.v = s32(a % b); } break; }
      case 0x20: r[rd] = s32(r[rs] + r[rt]); break;           // add (no trap)
      case 0x21: r[rd] = s32(r[rs] + r[rt]); break;           // addu
      case 0x22: r[rd] = s32(r[rs] - r[rt]); break;           // sub (no trap)
      case 0x23: r[rd] = s32(r[rs] - r[rt]); break;           // subu
      case 0x24: r[rd] = r[rs] & r[rt]; break;
      case 0x25: r[rd] = r[rs] | r[rt]; break;
      case 0x26: r[rd] = r[rs] ^ r[rt]; break;
      case 0x27: r[rd] = ~(r[rs] | r[rt]) | 0; break;         // nor
      case 0x2A: r[rd] = s32(r[rs]) < s32(r[rt]) ? 1 : 0; break;
      case 0x2B: r[rd] = u32(r[rs]) < u32(r[rt]) ? 1 : 0; break;
      default: die('unsupported instruction 0x' + u32(inst).toString(16) + ' at 0x' + pc.toString(16), 2);
    }
    return null;
  }
  if (op === 0x01) {                                          // REGIMM
    const take = rt === 0 ? (s32(r[rs]) < 0) :
                 rt === 1 ? (s32(r[rs]) >= 0) :
                 rt === 16 ? (s32(r[rs]) < 0) :
                 rt === 17 ? (s32(r[rs]) >= 0) : null;
    if (take === null) die('unsupported REGIMM rt=' + rt, 2);
    if (rt >= 16) r[31] = s32(pc + 8);                        // bltzal/bgezal
    return take ? u32(npc + (simm << 2)) : null;
  }
  switch (op) {
    case 0x02: return ((npc & 0xF0000000) | ((inst & 0x3FFFFFF) << 2)) >>> 0;   // j
    case 0x03: r[31] = s32(pc + 8);                                   // jal
               return ((npc & 0xF0000000) | ((inst & 0x3FFFFFF) << 2)) >>> 0;
    case 0x04: return r[rs] === r[rt] ? u32(npc + (simm << 2)) : null; // beq
    case 0x05: return r[rs] !== r[rt] ? u32(npc + (simm << 2)) : null; // bne
    case 0x06: return s32(r[rs]) <= 0 ? u32(npc + (simm << 2)) : null; // blez
    case 0x07: return s32(r[rs]) > 0 ? u32(npc + (simm << 2)) : null;  // bgtz
    case 0x08: r[rt] = s32(r[rs] + simm); break;                       // addi (no trap)
    case 0x09: r[rt] = s32(r[rs] + simm); break;                       // addiu
    case 0x0A: r[rt] = s32(r[rs]) < simm ? 1 : 0; break;               // slti
    case 0x0B: r[rt] = u32(r[rs]) < u32(simm) ? 1 : 0; break;          // sltiu
    case 0x0C: r[rt] = r[rs] & imm; break;                             // andi
    case 0x0D: r[rt] = r[rs] | imm; break;                             // ori
    case 0x0E: r[rt] = r[rs] ^ imm; break;                             // xori
    case 0x0F: r[rt] = s32(imm << 16); break;                          // lui
    case 0x20: r[rt] = s32((read8(u32(r[rs] + simm)) << 24) >> 24); break;  // lb
    case 0x21: r[rt] = s32((read16(algn(u32(r[rs] + simm), 2)) << 16) >> 16); break;   // lh
    case 0x23: r[rt] = read32(algn(u32(r[rs] + simm), 4)); break;                      // lw
    case 0x24: r[rt] = read8(u32(r[rs] + simm)); break;                                // lbu
    case 0x25: r[rt] = read16(algn(u32(r[rs] + simm), 2)); break;                      // lhu
    case 0x28: write8(u32(r[rs] + simm), r[rt]); break;                                // sb
    case 0x29: write16(algn(u32(r[rs] + simm), 2), r[rt] & 0xFFFF); break;             // sh
    case 0x2B: write32(algn(u32(r[rs] + simm), 4), r[rt]); break;                      // sw
    default: die('unsupported instruction 0x' + u32(inst).toString(16) + ' at 0x' + pc.toString(16), 2);
  }
  return null;
}

// main loop with branch delay slots
for (;;) {
  if (++steps > STEP_LIMIT) die('instruction budget exhausted', 9);
  const inst = fetch32(pc);
  const target = execute(inst);      // branches return their target
  pc = npc;
  npc = (target !== null && target !== undefined) ? target : (pc + 4) >>> 0;
}
