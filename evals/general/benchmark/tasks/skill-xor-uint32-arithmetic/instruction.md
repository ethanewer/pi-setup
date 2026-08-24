In `/app` there is `data.json` containing two unsigned 32-bit integers `a` and `b`, both in the range 0..4294967295 (2³²−1).

Write `/app/proc.py` that:
1. reads `a` and `b` from `/app/data.json`,
2. treats them as **unsigned 32-bit** values, so addition **wraps around modulo 2³²** (e.g. 0xFFFFFFFF + 1 wraps to 0),
3. computes `a XOR b` (bitwise exclusive-or),
4. writes `/app/result.json` containing exactly:

```json
{"a": <a>, "b": <b>, "sum_wrapped": <(a+b) mod 2^32>, "xor": <a XOR b>}
```

Then run your script so `/app/result.json` is produced with correct integer values.