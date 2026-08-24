# Identify a performance bottleneck with profiling

`/app/workload.py` is a small Python program that calls three functions named
`compute_fast`, `compute_mid`, and `compute_slow`. One of them dominates the
program's runtime.

Use **profiling** to find out which function consumes the most CPU time:

```
python3 -m cProfile -o /tmp/prof.out /app/workload.py
```

Then inspect the profile (e.g. with the `pstats` module) or use
`python3 -m cProfile -s tottime /app/workload.py` to print a sorted report.

Identify the function — out of `compute_fast`, `compute_mid`, `compute_slow` —
that has the largest **own (total) execution time** (tottime / "internal time" in
the cProfile report). Write exactly that function name (e.g. `compute_slow`) to
`/app/answer.txt`, followed by a newline.

When done, confirm `/app/answer.txt` exists and contains only the name of the
slowest function.