# Kinematic event detection

`/app/motion.csv` is a CSV with a header row and evenly timed samples; each row is:

```
t,x
```

where `t` is time and `x` is position (e.g. meters). Successive samples are 1 time unit apart, so the **velocity** at each step is `x[i+1] - x[i]` (finite difference).

Detect the first **direction reversal** — the earliest step where the object stops moving forward and reverses direction. Formally: find the smallest index `i` such that

- `x[i+1] - x[i]` changes sign relative to the previous nonzero step of the same type, i.e. the object was moving in `+t` direction and then starts moving in `-t` direction.

Write to `/app/event.txt` the **time `t` at which the reversal occurs** (the `t` of the turning point row — the last row where the object was still moving forward), as a plain decimal string ending with a newline.

Implementation hint (velocity is the slope between consecutive samples; a reversal from forward to backward is the first time the slope goes from positive to negative):

```python
import csv
rows = [r for r in csv.DictReader(open('/app/motion.csv'))]
x = [float(r['x']) for r in rows]
ts = [float(r['t']) for r in rows]
prev = None
for i in range(len(x) - 1):
    v = x[i+1] - x[i]
    if prev is not None and prev > 0 and v < 0:
        print(ts[i])
        break
    if v != 0:
        prev = v
```

Write the printed time to `/app/event.txt`.