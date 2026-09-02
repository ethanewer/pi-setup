Two Python functions in `/app/candidates.py`, `impl_a(n)` and `impl_b(n)`, both compute the same quantity (the sum of squares `1*1 + 2*2 + ... + n*n`) using different approaches with different time complexity. Both return correct integer results.

Benchmark them empirically:
1. Write a program `/app/bench.py`.
2. It should time both functions with the same fairly large input `n` (use n = 5000000) using `time.perf_counter()` inside a small timing loop. Run multiple repetitions per function (e.g. 10) and keep the *minimum* measured time in each case to reduce scheduler noise.
3. Determine which implementation is SLOWER.
4. Write `/app/bench.json` (a JSON object) with keys: `winner_slower` (the string `"A"` or `"B"` naming the slower function), `time_a_sec` and `time_b_sec` (each rounded to 4 decimals), and `reps` (an int).

Run your program to produce `/app/bench.json`. The verifier repeats the same measurement with the same fixed setup and checks that your reported slower implementation agrees with its own measurement.
