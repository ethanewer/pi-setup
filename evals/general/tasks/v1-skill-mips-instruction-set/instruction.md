In `/app` there is a file `instructions.txt` containing three raw 32-bit MIPS machine code words, one per line. Each line looks like `0x…………` (hexadecimal).

Write a Python script `/app/decode.py` that reads each word and decodes it using the standard MIPS instruction encoding for 32-bit little-level bit fields (bit 31 is the most significant):

- **R-type** instructions have opcode bits `[31:26] == 0`. Fields:
  - `rs` = bits `[25:21]` (register index)
  - `rt` = bits `[20:16]`
  - `rd` = bits `[15:11]`
  - `shamt` = bits `[10:6]`
  - `funct` = bits `[5:0]`
- **I-type** instructions have a nonzero opcode in `[31:26]`. Fields:
  - `rs` = bits `[25:21]`
  - `rt` = bits `[20:16]`
  - `imm` = bits `[15:0]` (the raw 16-bit immediate value)

Use this mnemonic table (by funct for R-type, by opcode for I-type):
- funct `0x20` → `add`
- funct `0x22` → `sub`
- opcode `0x08` → `addi`
- opcode `0x23` → `lw`
- anything else → `unknown`

Write `/app/decode.json` as a JSON array, with one element per line of `instructions.txt` in order, of exactly the following shapes:

For a decoded R-type instruction:
```json
{"word": "0x????????", "type": "R", "format": "add", "rd": 8, "rs": 9, "rt": 10, "shamt": 0}
```

For an I-type instruction:
```json
{"word": "0x????????", "type": "I", "format": "lw", "rs": 11, "rt": 8, "imm": 12}
```

For an unrecognized type, use `"format": "unknown"` and include `"opcode"` with the raw opcode integer instead of the type-specific fields.

Run the script so `/app/decode.json` exists with the correct contents.