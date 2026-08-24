At `/app/calc.c` there is a single C program. It is compiled in two modes:

- **debug build**: `gcc calc.c -o run_dbg` — assertions enabled (`NDEBUG` not defined)
- **release build**: `gcc -DNDEBUG calc.c -o run_rel` — assertions compiled out

Currently, running the same input produces different behavior in the two builds: the debug build **aborts on an `assert` failure** (SIGABRT, no output), while the release build silently prints `out=0`. The program relies on a debug-only assertion for what should be ordinary input handling.

Fix `/app/calc.c` so that **both** builds:
1. exit with status code 0, and
2. print the identical line `out=0`.

The intended program semantics: negative input values are clamped to `0` before the arithmetic, so the invariant `x >= 0` always holds. Make the debug build honor the same behavior as the release build (clamp before asserting).

Verify locally, e.g.:
```
cd /app
gcc calc.c -o run_dbg && ./run_dbg
gcc -DNDEBUG calc.c -o run_rel && ./run_rel
```

The verifier recompiles your `/app/calc.c` exactly twice — once without `-DNDEBUG` and once with `-DNDEBUG` — runs both binaries, and requires that each prints `out=0` and exits 0.
