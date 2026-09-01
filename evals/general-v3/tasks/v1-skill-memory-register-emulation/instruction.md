# Memory / register emulation

Emulate a tiny 4-register, 8-cell-memory machine. `/app/program.txt` contains the program:

```
LDI R0 3
LDI R1 4
MUL R2 R0 R1
ADD R3 R0 R1
STORE 1 R2
LOAD R1 1
HLT
```

Instruction set (executed in order until `HLT`):

- `LDI Rk imm`  → `Rk = imm`
- `ADD Rk Ra Rb` → `Rk = Ra + Rb`
- `SUB Rk Ra Rb` → `Rk = Ra - Rb`
- `MUL Rk Ra Rb` → `Rk = Ra * Rb`
- `MOV Rk Ra`   → `Rk = Ra`
- `STORE addr Rk` → `mem[addr] = Rk`  (memory addresses `0..7`, all start at `0`)
- `LOAD Rk addr` → `Rk = mem[addr]`
- `HLT`         → stop, and `HLT` must appear exactly once at the end

Initial registers: `R0 = R1 = R2 = R3 = 0`.

Write a small interpreter (`vm.py` is a fine name) in `/app/`, run it on `/app/program.txt`, and write the **final register file** to `/app/reg.json` like:

```json
{"R0": 3, "R1": 12, "R2": 12, "R3": 7}
```

Trace (for verification): `R0=3`, `R1=4`; `MUL` → `R2=12`; `ADD` → `R3=7`; `STORE 1 R2` → `mem[1]=12`; `LOAD R1 1` → `R1=12`.