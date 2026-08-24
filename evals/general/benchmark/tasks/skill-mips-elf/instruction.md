In `/app` there is a binary file `binary.elf` containing an ELF executable header.

Write a Python script `/app/elf_info.py` that:

1. Opens `/app/binary.elf` in binary mode.
2. Verifies the ELF magic (the first 4 bytes are `0x7f`, `'E'`, `'L'`, `'F'`).
3. Reads the ELF identity bytes:
   - byte `e_ident[4]` = ELF class (`1` for 32-bit, `2` for 64-bit)
   - byte `e_ident[5]` = endianness (`1` = little-endian, `2` = big-endian)
4. Interprets the header as little-endian 32-bit ELF and reads these fields:
   - `e_machine` (unsigned 16-bit, at byte offset 18)
   - `e_entry` (unsigned 32-bit, at byte offset 24)
5. Writes `/app/elf_report.json` as exactly:
```json
{"is_mips": true, "machine": 8, "class": 1, "endian": "little", "entry": 4194304, "ehsize": 52}
```

Only write `is_mips: true` if `e_machine == 8` (the ELF machine code for MIPS). Otherwise set it to `false`. The `class` value is `1` for 32-bit and `2` for 64-bit; `endian` is the string `"little"` when encoding is `1` and `"big"` otherwise.

Run the script so `/app/elf_report.json` exists with the correct contents.