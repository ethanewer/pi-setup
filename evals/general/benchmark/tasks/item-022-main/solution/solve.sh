#!/bin/bash
set -euo pipefail

cat > /app/parse.js <<'JS'
const fs = require('fs');
const buf = fs.readFileSync('/app/prog.elf');
const filesize = buf.length;
const BE = buf[5] === 2;

const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length);
const v = new DataView(ab);

const u16 = (o) => (BE ? v.getUint16(o) : v.getUint16(o, true));
const u32 = (o) => (BE ? v.getUint32(o) : v.getUint32(o, true));
const u64 = (o) => Number(BE ? v.getBigUint64(o) : v.getBigUint64(o, true));

const etype = u16(4);
const machine = u16(18);
const entry_va = u64(24);
const phoff = u64(32);
const shoff = u64(40);
const phentsize = u16(54);
const phnum = u16(56);
const shentsize = u16(58);
const shnum = u16(60);
const shstrndx = u16(62);

const program_headers = [];
for (let i = 0; i < phnum; i++) {
  const o = phoff + i * phentsize;
  program_headers.push({
    p_offset: u64(o + 8),
    p_vaddr: u64(o + 16),
    p_filesz: u64(o + 32),
  });
}

const sections_raw = [];
for (let i = 0; i < shnum; i++) {
  const o = shoff + i * shentsize;
  sections_raw.push({
    name_off: u32(o),
    sh_type: u32(o + 4),
    sh_addr: u64(o + 16),
    sh_offset: u64(o + 24),
    sh_size: u64(o + 32),
  });
}

function readNulString(base) {
  const bytes = [];
  let i = base;
  while (i < filesize && buf[i] !== 0) { bytes.push(buf[i]); i++; }
  return Buffer.from(bytes).toString('utf8');
}

const tabBase = sections_raw[shstrndx].sh_offset;
function nameStr(s) {
  if (s.name_off === 0) return '';
  return readNulString(tabBase + s.name_off);
}

let entry_section = null;
let entry_file_offset = null;
for (const s of sections_raw) {
  const lo = s.sh_addr;
  const hi = lo + s.sh_size;
  if (lo <= entry_va && entry_va < hi) {
    const fileBacked = (s.sh_type !== 8) && (s.sh_offset < filesize);
    if (fileBacked) {
      entry_section = nameStr(s);
      entry_file_offset = s.sh_offset + (entry_va - s.sh_addr);
      break;
    }
  }
}

const sections = sections_raw.map((s) => ({
  name: nameStr(s),
  sh_addr: s.sh_addr,
  sh_offset: s.sh_offset,
  sh_size: s.sh_size,
}));

const out = {
  header: {
    byte_order: BE ? 'big' : 'little',
    elf_type: etype,
    machine: machine,
    entry_va: entry_va,
  },
  program_headers,
  sections,
  entry_section,
  entry_file_offset,
};

fs.writeFileSync('/app/elf.json', JSON.stringify(out));
console.log(JSON.stringify(out, null, 2));
JS

node /app/parse.js