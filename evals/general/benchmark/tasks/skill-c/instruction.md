In `/app` there is a text file `data.txt` containing one integer per line (6 integers
total, e.g. `4`, `8`, `15`, …).

Write a **C++** program at `/app/stats.cpp` (use the C++ standard library: `iostream`,
`vector`, etc.) that reads all integers from `/app/data.txt` and prints exactly three
lines to stdout:

```
sum=108
count=6
avg=18.0
```

Rules:
- `sum` is the sum of all integers.
- `count` is the number of integers.
- `avg` is the arithmetic mean printed with exactly one decimal place (use e.g.
  `printf("%.1f", ...)` or iostream with fixed/setprecision(1)).

Then compile and run it, e.g.:

```bash
g++ -O2 -o /app/stats /app/stats.cpp
/app/stats
```

The verifier recompiles `/app/stats.cpp` with `g++` and compares its output against the
expected values recomputed from `/app/data.txt`.