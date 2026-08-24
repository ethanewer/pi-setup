# This helper is copied to /tests/ by the harness and NOT included in the
# agent image, so it can encode the exact expected structure without leaking
# anything the agent gets to inspect.
import json
import struct
import sys

ELF = '/app/prog.elf'
RESULT = '/app/elf.json'

d = open(ELF, 'rb').read()
filesize = len(d)
BE = d[5] == 2
E = '>' if BE else '<'


def r_u16(o):
    return struct.unpack_from(E + 'H', d, o)[0]


def r_u32(o):
    return struct.unpack_from(E + 'I', d, o)[0]


def r_u64(o):
    return struct.unpack_from(E + 'Q', d, o)[0]


etype = r_u16(4)
machine = r_u16(18)
entry_va = r_u64(24)
phoff = r_u64(32)
shoff = r_u64(40)
phentsize = r_u16(54)
phnum = r_u16(56)
shentsize = r_u16(58)
shnum = r_u16(60)
shstrndx = r_u16(62)

program_headers = []
for i in range(phnum):
    o = phoff + i * phentsize
    program_headers.append({
        'p_offset': r_u64(o + 8),
        'p_vaddr': r_u64(o + 16),
        'p_filesz': r_u64(o + 32),
    })

sections_raw = []
for i in range(shnum):
    o = shoff + i * shentsize
    sections_raw.append({
        'name_off': r_u32(o),
        'sh_type': r_u32(o + 4),
        'sh_addr': r_u64(o + 16),
        'sh_offset': r_u64(o + 24),
        'sh_size': r_u64(o + 32),
    })

tab_base = sections_raw[shstrndx]['sh_offset']


def name_str(noff):
    if noff == 0:
        return ''
    off = tab_base + noff
    end = off
    while end < filesize and d[end] != 0:
        end += 1
    return d[off:end].decode('utf-8')


sections = []
for s in sections_raw:
    sections.append({
        'name': name_str(s['name_off']),
        'sh_addr': s['sh_addr'],
        'sh_offset': s['sh_offset'],
        'sh_size': s['sh_size'],
    })

entry_section = None
entry_file_offset = None
for s in sections_raw:
    lo = s['sh_addr']
    hi = lo + s['sh_size']
    if lo <= entry_va < hi:
        file_backed = (s['sh_type'] != 8) and (s['sh_offset'] < filesize)
        if file_backed:
            entry_section = name_str(s['name_off'])
            entry_file_offset = s['sh_offset'] + (entry_va - s['sh_addr'])
            break

expected = {
    'header': {
        'byte_order': 'big' if BE else 'little',
        'elf_type': etype,
        'machine': machine,
        'entry_va': entry_va,
    },
    'program_headers': program_headers,
    'sections': sections,
    'entry_section': entry_section,
    'entry_file_offset': entry_file_offset,
}

with open(RESULT) as f:
    got = json.load(f)

assert got == expected
print('OK')
sys.exit(0)