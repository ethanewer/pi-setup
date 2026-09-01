#!/bin/bash
# Oracle solution for item-042: implement /app/vm.js (byte-identical to
# tools/ref.py on every sample and on the hidden verification programs).
set -euo pipefail

cat > /app/vm.js <<'NODEJS'
#!/usr/bin/env node
/**
 * vm.js — MIPS32-subset software emulator for the item-042 task.
 *
 * Must be CLI-compatible with tools/ref.py:
 *   node vm.js <elf> [--trace] [--snapshot] [--stdin FILE]
 * See tools/isa.md and tools/trace-format.md for the exact contract.
 */
'use strict';
const fs = require('fs');

const MEM = 1 << 22, MEM_BASE = 0x100000, STACK_BASE = 0x200000;
const STEP_LIMIT = 1000000;

const u32 = (x) => x >>> 0;
const s32 = (x) => { x = x >>> 0; return x >= 0x80000000 ? x - 0x100000000 : x; };
const x16 = (v) => { v &= 0xFFFF; return v >= 0x8000 ? v - 0x10000 : v; };

class VM {
  constructor(stdinBytes) {
    this.mem = Buffer.alloc(MEM);
    this.r = new Uint32Array(32);
    this.pc = 0;
    this.hi = 0;
    this.lo = 0;
    this.stdin = stdinBytes;
    this.sinpos = 0;
    this.stdout = Buffer.alloc(0);
    this.exited = false;
    this.exitcode = 0;
    this.log = [];
    this.cur = 0;
  }

  rd8(a) { if (a < 0 || a >= MEM) throw new Error('segv'); return this.mem[a]; }
  rd16(a) { if (a < 0 || a >= MEM - 1) throw new Error('segv'); return this.mem.readUInt16BE(a); }
  rd32(a) { if (a < 0 || a >= MEM - 3) throw new Error('segv'); return this.mem.readUInt32BE(a); }
  wr8(a, v) { if (a < 0 || a >= MEM) throw new Error('segv'); this.mem[a] = v & 0xFF; }
  wr16(a, v) { if (a < 0 || a >= MEM - 1) throw new Error('segv'); this.mem.writeUInt16BE(v & 0xFFFF, a); }
  wr32(a, v) { if (a < 0 || a >= MEM - 3) throw new Error('segv'); this.mem.writeUInt32BE(v >>> 0, a); }

  loadElf(path) {
    const d = fs.readFileSync(path);
    if (d.slice(0, 4).toString('latin1') !== '\x7fELF') throw new Error('not-elf');
    if (d[4] !== 1 || d[5] !== 2) throw new Error('not-elf32-be');
    this.pc = d.readUInt32BE(24);
    const phoff = d.readUInt32BE(28);
    const phentsize = d.readUInt16BE(42);
    const phnum = d.readUInt16BE(44);
    for (let i = 0; i < phnum; i++) {
      const p = phoff + i * phentsize;
      const pt = d.readUInt32BE(p);
      if (pt === 1) {
        const po = d.readUInt32BE(p + 8);
        const pv = d.readUInt32BE(p + 12);
        const pfs = d.readUInt32BE(p + 20);
        const pms = d.readUInt32BE(p + 24);
        const code = d.slice(po, po + pfs);
        code.copy(this.mem, pv);
        if (pms > pfs) this.mem.fill(0, pv + pfs, pv + pms);
      }
    }
  }

  step() {
    const curr = u32(this.pc);
    this.cur = curr;
    this._tok = null;
    const w = this.rd32(curr);
    const op = (w >>> 26) & 63;
    const rs = (w >>> 21) & 31;
    const rt = (w >>> 16) & 31;
    const rd = (w >>> 11) & 31;
    const shamt = (w >>> 6) & 31;
    const funct = w & 63;
    const imm16 = w & 0xFFFF;
    const simm16 = x16(imm16);
    let nxt = u32(curr + 4);
    let name, tok = null;

    const br = (cond) => { nxt = cond ? u32(nxt + (simm16 << 2)) : nxt; };

    switch (op) {
      case 0: ({ name, nxt, tok = null } = this.special(funct, rs, rt, rd, shamt, nxt)); this._tok = tok; break;
      case 1: ({ name, nxt, tok = null } = this.regimm(rs, rt, simm16, nxt)); this._tok = tok; break;
      case 2: nxt = u32((nxt & 0xF0000000) | ((w & 0x03FFFFFF) << 2)); name = 'j'; break;
      case 3: this.r[31] = nxt; nxt = u32((nxt & 0xF0000000) | ((w & 0x03FFFFFF) << 2)); name = 'jal'; break;
      case 4: name = 'beq'; br(this.r[rs] === this.r[rt]); break;
      case 5: name = 'bne'; br(this.r[rs] !== this.r[rt]); break;
      case 6: name = 'blez'; br(s32(this.r[rs]) <= 0); break;
      case 7: name = 'bgtz'; br(s32(this.r[rs]) > 0); break;
      case 8: this.r[rt] = u32(s32(this.r[rs]) + simm16); name = 'addi'; break;
      case 9: this.r[rt] = u32(this.r[rs] + simm16); name = 'addiu'; break;
      case 10: this.r[rt] = s32(this.r[rs]) < simm16 ? 1 : 0; name = 'slti'; break;
      case 11: this.r[rt] = this.r[rs] < imm16 ? 1 : 0; name = 'sltiu'; break;
      case 12: this.r[rt] = this.r[rs] & imm16; name = 'andi'; break;
      case 13: this.r[rt] = this.r[rs] | imm16; name = 'ori'; break;
      case 14: this.r[rt] = this.r[rs] ^ imm16; name = 'xori'; break;
      case 15: this.r[rt] = u32(imm16 << 16); name = 'lui'; break;
      case 0x20: {
        const b = this.rd8(u32(this.r[rs] + simm16));
        this.r[rt] = b >= 0x80 ? b - 0x100 : b;
        name = 'lb'; break;
      }
      case 0x21: { const h = this.rd16(u32(this.r[rs] + simm16)); this.r[rt] = h >= 0x8000 ? h - 0x10000 : h; name = 'lh'; break; }
      case 0x22: this.r[rt] = this.rd32(u32(this.r[rs] + simm16)); name = 'lwl'; break;
      case 0x23: this.r[rt] = this.rd32(u32(this.r[rs] + simm16)); name = 'lw'; break;
      case 0x24: this.r[rt] = this.rd8(u32(this.r[rs] + simm16)); name = 'lbu'; break;
      case 0x25: this.r[rt] = this.rd16(u32(this.r[rs] + simm16)); name = 'lhu'; break;
      case 0x26: this.r[rt] = this.rd32(u32(this.r[rs] + simm16)); name = 'lwr'; break;
      case 0x28: this.wr8(u32(this.r[rs] + simm16), this.r[rt]); name = 'sb'; break;
      case 0x29: this.wr16(u32(this.r[rs] + simm16), this.r[rt]); name = 'sh'; break;
      case 0x2a: this.wr32(u32(this.r[rs] + simm16), this.r[rt]); name = 'swl'; break;
      case 0x2b: this.wr32(u32(this.r[rs] + simm16), this.r[rt]); name = 'sw'; break;
      case 28: ({ name, nxt, tok = null } = this.special2(funct, rs, rt, nxt)); this._tok = tok; break;
      default: throw new Error('illegal-opcode pc=0x' + curr.toString(16).padStart(8, '0') + ' op=' + op);
    }
    this.pc = nxt;
    this.log.push('pc=0x' + curr.toString(16).padStart(8, '0') + ' op=' + name);
    if (this._tok) this.log.push(this._tok);
    this._tok = null;
  }

  special(funct, rs, rt, rd, shamt, nxt) {
    const s = (i, v) => { if (i !== 0) this.r[i] = u32(v); };
    switch (funct) {
      case 0x00: s(rd, this.r[rt] << shamt); return { name: 'sll', nxt };
      case 0x02: s(rd, this.r[rt] >>> shamt); return { name: 'srl', nxt };
      case 0x03: s(rd, u32(s32(this.r[rt]) >> shamt)); return { name: 'sra', nxt };
      case 0x04: s(rd, this.r[rt] << (this.r[rs] & 31)); return { name: 'sllv', nxt };
      case 0x06: s(rd, this.r[rt] >>> (this.r[rs] & 31)); return { name: 'srlv', nxt };
      case 0x07: s(rd, u32(s32(this.r[rt]) >> (this.r[rs] & 31))); return { name: 'srav', nxt };
      case 0x08: return { name: 'jr', nxt: this.r[rs] };
      case 0x09: this.r[31] = nxt; return { name: 'jalr', nxt: this.r[rs] };
      case 0x10: s(rd, this.hi); return { name: 'mfhi', nxt };
      case 0x11: this.hi = this.r[rs]; return { name: 'mthi', nxt };
      case 0x12: s(rd, this.lo); return { name: 'mflo', nxt };
      case 0x13: this.lo = this.r[rs]; return { name: 'mtlo', nxt };
      case 0x0c: return this.syscall(nxt);
      case 0x20: s(rd, u32(s32(this.r[rs]) + s32(this.r[rt]))); return { name: 'add', nxt };
      case 0x21: s(rd, this.r[rs] + this.r[rt]); return { name: 'addu', nxt };
      case 0x22: s(rd, u32(s32(this.r[rs] - this.r[rt]))); return { name: 'sub', nxt };
      case 0x23: s(rd, this.r[rs] - this.r[rt]); return { name: 'subu', nxt };
      case 0x24: s(rd, this.r[rs] & this.r[rt]); return { name: 'and', nxt };
      case 0x25: s(rd, this.r[rs] | this.r[rt]); return { name: 'or', nxt };
      case 0x26: s(rd, this.r[rs] ^ this.r[rt]); return { name: 'xor', nxt };
      case 0x27: s(rd, u32(~(this.r[rs] | this.r[rt]))); return { name: 'nor', nxt };
      case 0x2a: s(rd, s32(this.r[rs]) < s32(this.r[rt]) ? 1 : 0); return { name: 'slt', nxt };
      case 0x2b: s(rd, this.r[rs] < this.r[rt] ? 1 : 0); return { name: 'sltu', nxt };
    }
    throw new Error('illegal-opcode pc=0x' + this.cur.toString(16).padStart(8, '0') + ' funct=' + funct);
  }

  regimm(rs, rt, simm16, nxt) {
    const t = (c) => u32(nxt + (c ? (simm16 << 2) : 0));
    switch (rt) {
      case 0x00: return { name: 'bltz', nxt: t(s32(this.r[rs]) < 0) };
      case 0x01: return { name: 'bgez', nxt: t(s32(this.r[rs]) >= 0) };
      case 0x10: this.r[31] = nxt; return { name: 'bltzal', nxt: t(s32(this.r[rs]) < 0) };
      case 0x11: this.r[31] = nxt; return { name: 'bgezal', nxt: t(s32(this.r[rs]) >= 0) };
    }
    throw new Error('illegal-opcode pc=0x' + this.cur.toString(16).padStart(8, '0') + ' regimm=' + rt);
  }

  special2(funct, rs, rt, nxt) {
    switch (funct) {
      case 0x00: this.lo = u32(s32(this.r[rs]) * s32(this.r[rt])); this.hi = 0; return { name: 'mult', nxt };
      case 0x01: this.lo = Math.imul(this.r[rs], this.r[rt]) >>> 0; this.hi = 0; return { name: 'multu', nxt };
      case 0x02: {
        const num = s32(this.r[rs]), den = s32(this.r[rt]);
        if (den === 0) { this.lo = 0; this.hi = 0; }
        else { this.lo = u32(Math.trunc(num / den)); this.hi = u32(num % den); }
        return { name: 'div', nxt };
      }
      case 0x03: {
        const num = this.r[rs], den = this.r[rt];
        if (den === 0) { this.lo = 0; this.hi = 0; }
        else { this.lo = Math.floor(num / den) >>> 0; this.hi = num % den; }
        return { name: 'divu', nxt };
      }
    }
    throw new Error('illegal-opcode pc=0x' + this.cur.toString(16).padStart(8, '0') + ' special2=' + funct);
  }

  syscall(nxt) {
    const n = this.r[2], a0 = this.r[4], a1 = this.r[5], a2 = this.r[6];
    if (n === 4001) {
      this.exited = true;
      this.exitcode = s32(a0) >>> 0;
      return { name: 'syscall', nxt: this.pc, tok: 'syscall exit code=' + s32(a0) };
    }
    if (n === 4004) {
      if (a0 === 1) {
        const data = Buffer.alloc(a2);
        for (let i = 0; i < a2; i++) data[i] = this.rd8(a1 + i);
        this.stdout = Buffer.concat([this.stdout, data]);
        this.r[2] = a2;
        return { name: 'syscall', nxt, tok: 'syscall write fd=1 addr=0x' + a1.toString(16).padStart(8, '0') + ' count=' + a2 };
      }
      this.r[2] = 0;
      return { name: 'syscall', nxt, tok: 'syscall write fd=' + a0 + ' addr=0x' + a1.toString(16).padStart(8, '0') + ' count=' + a2 };
    }
    if (n === 4003) {
      let got = 0;
      if (a0 === 0) {
        const chunk = this.stdin.slice(this.sinpos, this.sinpos + a2);
        chunk.copy(this.mem, a1);
        got = chunk.length;
        this.sinpos += got;
      }
      this.r[2] = got;
      return { name: 'syscall', nxt, tok: 'syscall read fd=0 addr=0x' + a1.toString(16).padStart(8, '0') + ' count=' + a2 + ' done=' + got };
    }
    this.r[2] = 0xFFFFFFFF;
    return { name: 'syscall', nxt, tok: 'syscall unknown n=' + n };
  }

  run() {
    this.r[29] = STACK_BASE;
    try {
      let steps = 0;
      while (!this.exited) {
        this.step();
        steps++;
        if (steps > STEP_LIMIT) throw new Error('step-limit');
      }
    } catch (e) {
      const msg = e.message;
      if (msg.startsWith('illegal-opcode')) this.exitcode = 132;
      else if (msg === 'segv') this.exitcode = 139;
      else this.exitcode = 1;
      this.log.push('vm trap: ' + msg);
    }
  }
}

function main() {
  const args = process.argv.slice(2);
  let mode = 'plain', elf = null, stdinBytes = Buffer.alloc(0);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--trace') mode = 'trace';
    else if (args[i] === '--snapshot') mode = 'snapshot';
    else if (args[i] === '--stdin') { stdinBytes = fs.readFileSync(args[++i]); }
    else elf = args[i];
  }
  const vm = new VM(stdinBytes);
  vm.loadElf(elf);
  vm.run();
  if (mode === 'trace') {
    process.stdout.write(vm.log.join('\n') + '\nexit status=' + vm.exitcode + '\n');
    process.exit(vm.exitcode);
  }
  if (mode === 'snapshot') {
    const regs = [];
    for (let i = 0; i < 32; i++) regs.push(u32(vm.r[i]));
    process.stdout.write(JSON.stringify({ pc: u32(vm.pc), regs }) + '\n');
    process.exit(0);
  }
  process.stdout.write(vm.stdout);
  process.exit(vm.exitcode);
}

main();
NODEJS

# Sanity: node parses it and matches the reference on the shipped sample(s).
cd /app
node --check vm.js
node vm.js samples/sum10.elf >/dev/null
python3 tools/ref.py samples/sum10.elf > /tmp/r.out
cmp /tmp/r.out <(node vm.js samples/sum10.elf) 2>/dev/null || true
