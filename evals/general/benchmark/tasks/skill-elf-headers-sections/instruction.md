# ELF headers and section table

`/app/prog` is a small **ELF64** executable file (little-endian, x86-64
machine, `ET_EXEC`). It has a normal ELF header, one program header, and a
section header table with 3 entries (section index 0 is the NULL section).

## Task

Read the file's **ELF header** and **section header table** and answer these
questions with the *actual values found in the file*:

- `entry_point` — the `e_entry` field of the ELF header (virtual address of
  the entry point), as lowercase hex with `0x` prefix.
- `shoff` — the `e_shoff` field (file offset where the section header table
  starts), lowercase hex with `0x` prefix.
- `shnum` — the `e_shnum` field (number of section header entries), lowercase
  hex with `0x` prefix.
- `text_sh_offset` — the `sh_offset` field of the section named `.text`
  (sections are identified by name through the string table section, whose
  index is `e_shstrndx`), lowercase hex with `0x` prefix.
- `text_sh_size` — the `sh_size` field of the `.text` section, lowercase hex
  with `0x` prefix.

Write the answers to `/app/answer.txt` as one `key=value` line per answer,
with the keys exactly as listed above, e.g.:

```
entry_point=0x401000
shoff=0x80
shnum=0x3
text_sh_offset=0x140
text_sh_size=0x4
```

(Those are illustrative only — read the real values from the file.) The
verifier parses `/app/prog` itself with the same ELF structure rules and
compares each of the five values. You may use any tools installed (Python 3
with `struct` works everywhere) or hand-parse the binary.

## ELF64 reference (little-endian)

- ELF header: 16-byte `e_ident` (bytes `7f 45 4c 46`, class byte `2` = 64-bit,
  data byte `1` = little-endian), then at offset 16: `e_type` (2), `e_machine`
  (2), `e_version` (4), `e_entry` (8), `e_phoff` (8), `e_shoff` (8),
  `e_flags` (4), `e_ehsize` (2), `e_phentsize` (2), `e_phnum` (2),
  `e_shentsize` (2), `e_shnum` (2), `e_shstrndx` (2).
- Section header entry (64 bytes): `sh_name` (4), `sh_type` (4), `sh_flags`
  (8), `sh_addr` (8), `sh_offset` (8), `sh_size` (8), `sh_link` (4),
  `sh_info` (4), `sh_addralign` (8), `sh_entsize` (8).
- `sh_name` is a byte offset into the string table (`.shstrtab`); its section
  header is at index `e_shstrndx` in the section header table, and its content
  lives at that section's `sh_offset` (NUL-separated names).
