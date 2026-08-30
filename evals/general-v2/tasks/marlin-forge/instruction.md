# Marlin Forge — UPC-style shared-heap parallel assembly

Build a **UPC-style shared-memory parallel assembler** in C over pthreads and
run it on the visible input so the per-rank output files land in `/app`. The
verifier recompiles your source and runs the binary on hidden inputs, so
nothing may be hard-coded to the visible case.

## Deliverables

| path | what it is |
|---|---|
| `/app/assembly_upc.c` | the C source you author (pthread + shared-heap implementation) |
| `/app/agen` | the compiled binary, built with `gcc -O2 -pthread -o agen assembly_upc.c` |
| `/app/worker_<r>.dat` | the per-rank output files produced by running `./agen 4 37` from `/app` (4 files, `r = 0..3`) |

## Program contract

```
/app/agen <num_threads> <total_items>
```

- `num_threads >= 1`, `total_items >= 0` (both parsed as decimal integers,
  `long`-safe).
- On malformed arguments — wrong argument count (anything other than exactly
  2), `num_threads < 1`, or `total_items < 0` — print a usage message naming
  the program to **stderr** and **exit with status 3**. On invalid arguments
  **no `worker_*.dat` file** may be written.

### Deterministic per-item value

```
value(i) = (i * 4453 + 911) % 65521        # i is a long
```

### Shared-heap structure

The program must allocate **one** shared heap — a single `malloc`'d array of
`long` with exactly `total_items` cells — that **all threads** write into
concurrently (each thread storing the values of its own contiguous slice into
its slice of the heap before accumulating its totals). This mirrors a UPC
shared-array layout over `THREADS` threads.

### Work split

Thread `r` of `R` owns the contiguous half-open slice

```
lo = (total_items * r) / R        (integer division of non-negative longs)
hi = (total_items * (r + 1)) / R
```

All threads together cover `0 .. total_items-1` exactly once. When
`num_threads > total_items` some threads own an **empty slice** (`lo == hi`);
they must still write their own output file with `sum=0` and `max=0`. When
`total_items == 0`, every slice is empty and all `num_threads` files are still
written.

### Per-thread output file

Thread `r` writes a file named exactly `worker_<r>.dat` (prefix `worker_`,
suffix `.dat`, decimal rank id) **in the current working directory**, with
exactly these five lines and no trailing whitespace:

```
worker=<r>
span=<lo>:<hi>
sum=<sum of value(i) for i in [lo,hi)>
max=<max of value(i) over the slice; 0 for an empty slice>
valid=true
```

### Global check on exit

After the threads join, the program must verify that the accumulated grand
total (the sum of every thread's slice sum, e.g. combined through the shared
heap or a shared accumulator) equals `sum(value(i))` over `0 .. total_items-1`
computed serially. If the check fails, exit **non-zero**. On success exit **0**.

## Visible case

Running

```
cd /app && ./agen 4 37
```

must exit 0 and leave `/app/worker_0.dat`, `/app/worker_1.dat`,
`/app/worker_2.dat`, `/app/worker_3.dat` in place. These files are
deliverables and are byte-checked.

## Edge cases the hidden verify probes

- a serial run (`num_threads == 1`),
- a slice count that does **not** divide the item count evenly,
- `num_threads > total_items` (empty slices: `sum=0`, `max=0`, `span` with
  `lo == hi`),
- `total_items == 0` (all slices empty; all files still written),
- malformed argv: no args, `num_threads=0`, negative `total_items`, extra args
  → each must exit 3, write the usage to stderr, and write nothing.

## Rules

- Work only under `/app`. Do not read or import `/tests` or `/solution`.
- No network access.
- `/app/assembly_upc.c` must compile cleanly with `gcc -O2 -pthread`.
- Produce every deliverable by actually building and running your program —
  do not hand-write the `.dat` files.
