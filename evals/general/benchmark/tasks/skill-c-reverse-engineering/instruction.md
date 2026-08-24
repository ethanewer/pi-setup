In `/app` there is a compiled C program `chal` (usage: `/app/chal <password>`). It was
compiled from C source, but the source is **not** provided — you must reverse-engineer the
binary.

Behavior: when given the correct password as its single argument, it prints a flag line
beginning with `FLAG{...}`; otherwise it prints `access denied`.

The program transforms each byte of the password you supply with a **single fixed byte
constant via XOR** (`input_byte ^ KEY`) and compares the result against a table of encoded
bytes stored in the binary. The same key is used to encode the flag, which is why neither
the password nor the flag appears in plain text in `strings /app/chal`.

Your job — use reverse-engineering tooling available in the container (`strings`,
`objdump -d`/`objdump -s`, `readelf`, `xxd`) to:

1. Locate the XOR byte constant `KEY` and the encoded table.
2. Decode the password yourself (e.g. with a small `python3` one-liner that XORs the
   table bytes with `KEY`). The password is a short ASCII string like `r3v3rs3_m3`.
3. Run `/app/chal <password>` and confirm it prints the `FLAG{...}` line.
4. Save that exact flag line (the whole output line, including `FLAG{...}`) into
   `/app/flag.txt`.

Your `/app/flag.txt` is what gets verified: it must equal the output line produced by
executing the binary with the correct password.