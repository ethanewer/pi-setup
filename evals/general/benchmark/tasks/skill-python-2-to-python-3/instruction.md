# Port a Python 2 program to Python 3

`/app/legacy.py` is a small script originally written for Python 2. It reads comma-separated integers from `/app/input.txt`, computes their sum, count, and average, and prints a line of the form:

```
sum=<total> count=<count> avg=<avg>
```

Because it is Python 2, it uses:

- a `print` **statement** (not a function call), and
- **integer/floor division** (`/`) for the average.

The *correct* average here is the **real** quotient: the ten integers `1,2,...,10` sum to `55`, so `avg` should be `5.5` (not `5`).

Your job is to **port `/app/legacy.py` to Python 3** (edit the file in place):

1. Make `print` a function call (`print(...)`).
2. Make the average use **true division** so `avg == 5.5`.
3. Keep the same output format `sum=<total> count=<count> avg=<avg>`.

Then run the converted program with its stdout redirected to `/app/out.txt`:

```
python3 /app/legacy.py > /app/out.txt
```

`/app/out.txt` must then contain exactly one line:

```
sum=55 count=10 avg=5.5
```

The verifier runs `python3 /app/legacy.py` and checks it (a) runs without error under Python 3, (b) prints exactly that line, and (c) that a matching `/app/out.txt` exists.