In `/app/native` there are the sources of a small C library and tools that wrap it:

- `libcalc.h` / `libcalc.c` — a plain C library with `int calc_add(int,int)` and
  `int calc_sub(int,int)`.
- `quickwrap.cpp` — a **C++** CPython extension module named `quickcalc` (built with the
  Python C API) that re-exports the two C functions as `quickcalc.add(a,b)` and
  `quickcalc.sub(a,b)`.
- `calc_cli.c` — a small C command-line tool that prints `add=<a+b> sub=<a-b>` for two
  integer arguments.

Build and exercise **all three** pieces:

1. **Write** `/app/native/setup.py` using `setuptools` with an `Extension` named
   `quickcalc`, sources `["libcalc.c", "quickwrap.cpp"]`, `language="c++"`.
2. **Build the C++ extension** in place:

   ```bash
   cd /app/native
   python setup.py build_ext --inplace
   ```

   This must produce a `quickcalc.cpython-*.so` file in `/app/native`.
3. **Build the C CLI** by compiling it together with the C library:

   ```bash
   gcc -O2 -o /app/native/calc_cli /app/native/calc_cli.c /app/native/libcalc.c
   ```

4. **Verify both work**, then write `/app/native/build_report.json` containing exactly:

   ```json
   {"extension": "quickcalc", "cli_worked": true}
   ```

   where `quickcalc.add(7, 3) == 10`, `quickcalc.sub(7, 3) == 4`, and
   `/app/native/calc_cli 7 3` prints `add=10 sub=4`.

The verifier imports `quickcalc` from `/app/native`, checks both functions, runs the CLI
with `7 3`, and checks `/app/native/build_report.json`.