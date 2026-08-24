# ELF loading: mapping sections onto memory via program headers

`/app/prog` is a small **ELF64** executable (little-endian, x86-64). It has a
real **program header table** with 2 entries, both `PT_LOAD` (`p_type == 1`).
An ELF *loader* maps each `PT_LOAD` segment into memory: the file window
`[p_offset, p_offset + p_filesz)` is loaded at virtual addresses
`[p_vaddr, p_vaddr + p_filesz)`; memory from `p_vaddr + p_filesz` up to
`p_vaddr + p_memsz` is zero-filled (the BSS region).

A section whose `sh_offset` falls inside a segment's file window lands in
memory at:

```
section_va = segment.p_vaddr + (section.sh_offset - segment.p_offset)
```

The segment flags use the standard bitmask: `1` = executable, `2` = writable,
`4` = readable (a `PT_LOAD` with the writable bit set maps R/W data).

## Task

Read the program headers and the section header table of `/app/prog` and
answer:

- `nload` — number of `PT_LOAD` program headers, lowercase hex with `0x` prefix.
- `text_vaddr` — the memory virtual address at which the `.text` section is
  loaded, computed from the segment that contains it (formula above), hex `0x`.
- `data_vaddr` — the memory virtual address at which the `.data` section is
  loaded, computed from the segment that contains it, hex `0x`.
- `data_seg_end` — end (exclusive) of the memory range covered by the first
  writable `PT_LOAD` segment (`p_vaddr + p_memsz`), hex `0x`.

Write the answers to `/app/answer.txt` as one `key=value` line per answer with
the keys exactly as listed, all lowercase hex with `0x` prefix, e.g.:

```
nload=0x2
text_vaddr=0x400200
data_vaddr=0x601000
data_seg_end=0x601004
```

(Those are illustrative only — read the real values from the file.) The
verifier recomputes all four values from `/app/prog` itself using the same
loading rules.

## Reference

- ELF header (little-endian, 64-bit): at offset 16: `e_type` (2), `e_machine`
  (2), `e_version` (4), `e_entry` (8), `e_phoff` (8), `e_shoff` (8),
  `e_flags` (4), `e_ehsize` (2), `e_phentsize` (2), `e_phnum` (2),
  `e_shentsize` (2), `e_shnum` (2), `e_shstrndx` (2).
- Program header (56 bytes): `p_type` (4), `p_flags` (4), `p_offset` (8),
  `p_vaddr` (8), `p_paddr` (8), `p_filesz` (8), `p_memsz` (8), `p_align` (8).
- Section header (64 bytes): `sh_name` (4), `sh_type` (4), `sh_flags` (8),
  `sh_addr` (8), `sh_offset` (8), `sh_size` (8), `sh_link` (4), `sh_info` (4),
  `sh_addralign` (8), `sh_entsize` (8). Section names come from the string
  table whose section index is `e_shstrndx`.