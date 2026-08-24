Determining the **host ABI and architecture** is a basic systems skill. Under `/app/host/` is a small C source file `probe.c`. It is a runtime probe that prints one line describing the host:

- the width of a pointer in bits (`ARCH`),
- the byte order (`ENDIAN`, either `LE` or `BE`),
- the size of a pointer in bytes (`POINTER`).

1. Compile `probe.c` with gcc: `gcc -O2 -o /app/host/probe /app/host/probe.c`
2. Run the compiled probe: `/app/host/probe`
3. Capture its exact stdout (one line) and write that same line to `/app/host/abi.txt` (exactly one line, no trailing spaces; a trailing newline is fine).

On this x86-64 little-endian host the expected line is:

```
ARCH=64 ENDIAN=LE POINTER=8
```

Do not modify `probe.c`. The verifier recompiles and reruns `probe.c` on the same host and requires that `/app/host/abi.txt` exactly matches its output.