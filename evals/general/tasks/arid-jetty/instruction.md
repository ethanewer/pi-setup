# Arid Jetty — polyglot / low-level harness

You are working in `/app` on a Debian-24 base with `python3`, `nodejs` (v18+, with
the native `WebAssembly` API), and `vim` installed. Several prepared fixtures
already exist and must be treated as read-only inputs — do not edit any file under
`/app/data` or `/app/run`.

Your job is to write ONE program, `/app/solve.py`, that implements five
independent low-level behaviors described below, plus a driver `main()` that
produces `/app/answer.json` and a canonical Vimscript layout file
`/app/recreate.vim`. A hidden verifier will import `/app/solve.py`, re-run each
behavior, re-source the emitted Vimscript in a fresh `vim -u NONE`, and compare
everything against independently computed expectations, including the edge /
malformed / override cases described at the end.

## Deliverables (all must exist after `python3 /app/solve.py` runs with no args)

1. `/app/solve.py` — importable module implementing the exact API below.
2. `/app/answer.json` — JSON object written by `main()` with exactly the keys
   described under "answer.json format".
3. `/app/recreate.vim` — canonical Vimscript producing the required layout,
   written by `emit_vimscript()`.

## Fixtures provided in /app

- `/app/data/mem.wasm` — a tiny WebAssembly module. It exports a function `probe`
  (type `() -> i32`) that returns an **index into the module's linear memory**, and
  it exports its `memory`. A byte pattern is stored in linear memory starting at
  that same offset, so `memory[probe()]` is a predictable 0..255 byte.
- `/app/data/bad.wasm` — a deliberately malformed (non-wasm) byte blob, used to
  test error handling.
- `/app/data/compute_seq.py` — the companion *sequential* module. It defines the
  integer constant `ITERATIONS` (currently 731) that your parallel work must
  consume **by import**.
- `/app/data/buggy_point.py` — a reference `Point` whose `__eq__` is value-based
  but which relies on the default identity hash (the exact invariant you must fix;
  import nothing from it into your solution).
- `/app/run/alpha.txt`, `/app/run/beta.txt`, `/app/run/gamma.txt` — buffer files
  referenced by the Vimscript.

## Required API in /app/solve.py

### Part 1 — WebAssembly exported function returning a memory offset

`wasm_probe(binary=None) -> (int, int)`

- Instantiate given `.wasm` binary (default `/app/data/mem.wasm`) with a real
  WebAssembly runtime (recommend the Node.js `WebAssembly.instantiate` API,
  driven from Python via `subprocess`), call the exported `probe()`, and return
  `(offset, byte)` where `offset` is the exact integer probe() returned and
  `byte` is the value in **linear memory at that offset** (`0..255`).
- The default must return a plausible memory index and the byte stored there for
  `mem.wasm` — your program must actually read the memory, not guess.
- **Error handling (hidden cases probe this):** if `binary` does not exist, is
  not a real wasm binary (has no `\0asm` magic), or the module lacks the required
  `probe`/`memory` exports, `wasm_probe` must raise `ValueError` (with a
  descriptive message). It must never return a wrong value on malformed input.

### Part 2 — higher-order closures, currying, mutual recursion

- `make_counter(start) -> (inc, dec)`: returns two closures over ONE shared,
  mutable cell seeded with `start`. `inc(by=1)` adds `by` to the cell and returns
  the new value; `dec(by=1)` subtracts `by` and returns the new value. `by` may be
  negative or zero. Repeated calls observe the accumulated state (true shared
  mutable state, not a captured copy).
- `curry_add(a) -> f`: returns a curried function where `f(b)` returns `a + b`,
  and the variadic form `f(b, c)` returns `a + b + c`.
- `mutual_even(n) -> bool` and `mutual_odd(n) -> bool`: mutually recursive parity
  predicates. Negative inputs must be normalized (e.g. `mutual_even(-6)` is
  `True`, `mutual_odd(-7)` is `True`, `mutual_even(0)` is `True`,
  `mutual_odd(0)` is `False`). Raise the recursion limit if needed.
- `closure_probe() -> dict`: returns exactly
  `{"seq": [12, 13, -7, 0], "curry": 9, "even12": true, "odd13": true}` where
  `seq` comes from seeding a counter at 10 and applying `inc(2), inc(1), dec(20),
  inc(7)`, `curry` is `curry_add(4)(5)`, `even12` is `mutual_even(12)`, `odd13` is
  `mutual_odd(13)`.

### Part 3 — object hash consistent with equality

- A class `Point(x, y)` with value-based `__eq__` AND a `__hash__` derived from
  the same value tuple used by `__eq__`. Distinct but value-equal instances must
  hash identically; value-unequal instances must hash differently. (Ship a value
  tuple like `hash((self.x, self.y))`.)
- `hash_signature() -> dict`: returns exactly
  `{"equal": true, "equal_same_hash": true, "self_in_set": true,
  "unequal_diff_hash": true}` computed with `Point(2,3), Point(2,3), Point(2,4)`:
  `equal` = the two `(2,3)` points are `==`; `equal_same_hash` = they hash the
  same; `self_in_set` = `len({a, b, Point(2,3)}) == 1`; `unequal_diff_hash` =
  `Point(2,3) != Point(2,4)` and their hashes differ.

### Part 4 — sequential iteration constant consumed by import

- `get_iterations() -> int`: returns the `ITERATIONS` constant **imported from
  `/app/data/compute_seq.py`** (module-level import; do not copy the number).
- `compute_parallel() -> list`: returns a list whose length is **exactly**
  `compute_seq.ITERATIONS` read dynamically from the module attribute (e.g.
  `[i * 2 for i in range(compute_seq.ITERATIONS)]`). Because it must track the
  *live* attribute, if something changes `compute_seq.ITERATIONS` the length of
  this list must change too.
- HARD RULE: `/app/solve.py` must not contain the literal text `731` anywhere —
  the constant must only ever come from the import. The verifier greps the source.

### Part 5 — canonical Vimscript recreating a layout

- `emit_vimscript(path="/app/recreate.vim") -> str`: writes (and returns) a
  canonical, idempotent Vimscript that, when sourced in a FRESH `vim -u NONE`,
  reproduces exactly this topology:
  - exactly **2 tab pages**;
  - **tab 1** shows **2 windows** — buffer `alpha.txt` (opened first) and buffer
    `beta.txt` (opened with a horizontal `split`);
  - **tab 2** shows **1 window** — buffer `gamma.txt` (opened with `tabnew`).
  The body is the plain sequence of window/tab/buffer commands, e.g.:
  `set nocompatible`, `silent edit /app/run/alpha.txt`,
  `silent split /app/run/beta.txt`, `silent tabnew /app/run/gamma.txt`. No
  autocommands, no mappings, no `:source` recursion. The file paths are absolute
  `/app/run/...` paths.
- `main()` must call `emit_vimscript()` so the file lands at `/app/recreate.vim`.

## answer.json format (exactly these keys)

```json
{
  "wasm_offset": <int, from wasm_probe()>,
  "wasm_byte": <int 0..255, byte at that offset>,
  "closure": <same dict as closure_probe()>,
  "iterations": <int, get_iterations()>,
  "parallel_len": <int, len(compute_parallel())>,
  "hash_consistent": true,
  "vim_script": "/app/recreate.vim"
}
```

`main()` writes the above to `/app/answer.json` (any key order/whitespace is
fine). Every numeric field must be computed from the live functions above — never
hardcode the values.

## Hidden cases the verifier will run (your code must handle all)

1. **Closure edges**: counters seeded with negative/zero values stepped by
   `inc`/`dec` with negative and large deltas; curried calls with a negative `b`;
   parity checks on large even/odd and negative inputs, and `mutual_odd(0)`.
2. **Hash/equality**: pairs of equal and unequal points (zero coords, negative
   coords, large coords, swapped-coordinate distinct points). Equal points must
   hash identically; unequal points must hash differently.
3. **Malformed wasm**: `wasm_probe("/app/data/bad.wasm")` and
   `wasm_probe("/app/data/does_not_exist.wasm")` must each raise `ValueError`.
4. **Iteration-constant override**: the verifier temporarily sets
   `compute_seq.ITERATIONS = 42` and asserts `len(compute_parallel())` becomes 42
   (proving the length tracks the imported constant, not a hardcoded number), and
   also asserts the text `731` never appears in `/app/solve.py`.

## Constraints

- Work only in `/app`. Do not modify `/app/data/*` or `/app/run/*`.
- Do not install extra packages; everything you need is already present.
- `/app/solve.py` must run cleanly as `python3 /app/solve.py` (no args) to
  produce both outputs, and must also import cleanly (top-level `main()` must only
  run under `if __name__ == "__main__":`).
- Number literals are fixture values — derive them from the environment/files at
  runtime, never assume arbitrary constants other than those in this document
  (the closure probe values `12,13,-7,0`, `9` and the parity samples are fixed by
  this spec, not hardcoded guesses).
