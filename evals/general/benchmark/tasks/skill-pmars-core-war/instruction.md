# Core War warrior (Redcode)

Write a valid **Core War** warrior program in **Redcode**, the assembly language used by the pMARS simulator and other Core War MARS simulators ("Memory Array Redcode Simulator"). Save it as `/app/warrior.red`.

The file must satisfy all of the following:

- It is a plain-text Redcode source file.
- Every non-empty line is either:
  - a full-line comment (starts with `;`), a blank line is also fine, **or**
  - a single instruction of the form `[label:] MNEMONIC [.modifier] [operand[,operand]]`, where:
    - a `label` is an identifier ended by `:`,
    - `MNEMONIC` is one of the valid opcodes below,
    - an optional addressing `.modifier` (such as `.A`, `.B`, `.AB`, `.BA`, `.X`, `.F`, `.I`) may follow the mnemonic,
    - each operand may carry a mode prefix from `# $ @ < > * { } + -`, and operands are comma-separated for binary instructions.
- It contains **at least 3 instructions**.
- It contains **at least one `DAT`** instruction (a trap / data cell — the classic "bomb" cell used by dwarf/imp-style warriors).
- It contains **at least one control-transfer** instruction from this set: `JMP`, `JMZ`, `JMN`, `DJN`, `SPL`, `SLT`, `CMP`, `SEQ`, `SNE`.
- It uses **no** pseudo-operations or macros: no `ORG`, no `#define`, no `END`.

The full set of valid mnemonics is:

```
DAT MOV ADD SUB MUL DIV MOD
JMP JMZ JMN DJN CMP SLT
SPL SEQ SNE STP NOP
```

A classic example that readily satisfies all requirements is a small "dwarf" warrior: an `ADD` plus `MOV` pair that repeatedly copies a `DAT` cell, driven by a `JMP` loop. Any self-contained source meeting the requirements above is accepted — the verifier parses your file, checks the instruction grammar and mnemonic set, and confirms the count, control-flow, and `DAT` requirements.