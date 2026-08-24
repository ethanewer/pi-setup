# Parse the ELF file

In `/app` there is an ELF file `prog.elf`.  It is a small but structurally valid
64-bit ELF binary.  The file is either little- or big-endian and unpadded; you
must **inspect it** rather than assume a byte order or a layout.

The signatures you need are at fixed offsets in the file:

- byte 0: `0x7F`
- bytes 1-3: `'E','L','F'`
- byte 4: EI_CLASS — `1` = 32-bit class, `2` = 64-bit class (this file is class 2)
- byte 5: EI_DATA — `1` = little-endian (LSB), `2` = big-endian (MSB)

Read EI_DATA (byte 5) to decide the byte order, then parse the rest of the file
with that order.  Do not hard-code an endianness.

Write a Node.js program `/app/parse.js` that reads `/app/prog.elf` and writes
`/app/elf.json` containing **exactly** this JSON object:

```json
{
  "header": {
    "byte_order": "little" | "big",
    "elf_type": <int>,
    "machine": <int>,
    "entry_va": <int>
  },
  "program_headers": [
    {"p_offset": <int>, "p_vaddr": <int>, "p_filesz": <int>}
  ],
  "sections": [
    {"name": "<string>", "sh_addr": <int>, "sh_offset": <int>, "sh_size": <int>}
  ],
  "entry_section": "<string or null>",
  "entry_file_offset": <int or null>
}
```

How to parse the structures (64-bit class).

**ELF header** (64 bytes, fields in order):

| offset | type | field |
| --- | --- | --- |
| 0 | 16 bytes | e_ident (signature bytes) |
| 16 | u16 | e_type |
| 18 | u16 | e_machine |
| 20 | u32 | e_version |
| 24 | u64 | e_entry (virtual address of entry point) |
| 32 | u64 | e_phoff (file offset of program header table) |
| 40 | u64 | e_shoff (file offset of section header table) |
| 48 | u32 | e_flags |
| 52 | u16 | e_ehsize |
| 54 | u16 | e_phentsize |
| 56 | u16 | e_phnum |
| 58 | u16 | e_shentsize |
| 60 | u16 | e_shnum |
| 62 | u16 | e_shstrndx |

**Program header table** — starts at file offset `e_phoff`, exactly
`e_phnum` entries, each `e_phentsize` bytes.  Each entry in order:

| offset | size | field |
| --- | --- | --- |
| 0 | u32 | p_type |
| 4 | u32 | p_flags |
| 8 | u64 | p_offset (file offset of the segment's data) |
| 16 | u64 | p_vaddr |
| 24 | u64 | p_paddr |
| 32 | u64 | p_filesz |
| 40 | u64 | p_memsz |
| 48 | u64 | p_align |

The `program_headers` array in the output must contain one object per program
header, in table order, using its `p_offset`, `p_vaddr`, `p_filesz`.

**Section header table** — starts at file offset `e_shoff`, exactly
`e_shnum` entries, each `e_shentsize` (64) bytes. Each entry in order:

| offset | size | field |
| --- | --- | --- |
| 0 | u32 | sh_name (byte offset into the string table) |
| 4 | u32 | sh_type |
| 8 | u64 | sh_flags |
| 16 | u64 | sh_addr (virtual address) |
| 24 | u64 | sh_offset (file offset) |
| 32 | u64 | sh_size |
| 40 | u32 | sh_link |
| 44 | u32 | sh_info |
| 48 | u64 | sh_addralign |
| 56 | u64 | sh_entsize |

The `sections` array must contain one object per section header, in table
order, using the section name (below), `sh_addr`, `sh_offset`, `sh_size`.

**Section names** — the section at table index `e_shstrndx` is the string
table.  Its own `sh_offset` is the base file offset of that table.  A
section's `sh_name` is a byte offset into that same string table; the name is
the NUL-terminated UTF-8 string starting there.  (If the offset equals 0, the
section has an empty name.)

**entry_section** — scan the section headers **in table order**.  The first
section such that:

- `sh_addr <= entry_va < sh_addr + sh_size`, and
- the section is *file-backed*: `sh_type != 8` (8 is `SHT_NOBITS`, which has
  no file data) **and** `sh_offset <` file size.

wins.  Return its name; if none matches, use `null`.

`entry_file_offset` — the file byte offset of the entry point: if
`entry_section` is not null, it equals that section's `sh_offset +
(entry_va - sh_addr)`; otherwise `null`.

After writing `/app/elf.json`, run your program so the file exists with the
correct contents.