# Static binary analysis

`/app/prog` is a compiled ELF executable. You must analyze it **statically** (without executing it) and record facts about it. The GNU binutils tools `readelf`, `objdump`, `nm`, and `strings` are installed; the source file used to build it is **not** present in the image.

Extract the following three facts **from the binary itself**:

1. **ELF format** — run `objdump -f /app/prog` and take the `file format` field (e.g. `file format elf64-x86-64`).
2. **Entry point address** — run `readelf -h /app/prog`; the "Entry point address" line contains the entry point as a hex address (e.g. `0x401050`). Report it in lowercase hex with the `0x` prefix.
3. **A hidden secret string** — the binary's read-only data section contains a literal ASCII string `harbor-binary-secret-9621` (the return value of an internal function; it is never built into a longer string). Use `strings /app/prog` to recover it.

Write a short shell script `/app/analyze.sh` that produces `/app/analysis.txt` with exactly three lines:

```
elf=<file format value from objdump -f>
entry=<entry point in lowercase hex, e.g. entry=0x401050>
secret=harbor-binary-secret-9621
```

For example:

```
elf=file format elf64-x86-64
entry=0x401050
secret=harbor-binary-secret-9621
```

Then run `/app/analyze.sh` so `/app/analysis.txt` exists.

The verifier recomputes the same three facts from `/app/prog` on its own (with `objdump -f`, `readelf -h`, and `strings`) and requires your lines to match. Do not modify or recompile `/app/prog`.