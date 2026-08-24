# Pipeline parallelism

`/app/pipeline.py` defines a small text-processing pipeline over a fixed list of
items, with three named stages:

```python
ITEMS = ["  alpha  ", "beta", "  gamma", "delta"]

def stage1(s):
    return s.strip()          # trim whitespace

def stage2(s):
    return s.upper()           # uppercase

def stage3(s):
    return s + "!"           # add "!"
```

and a `run_sequential(items)` function that pushes each item through
the stages one after another and returns the processed output **in input order**.

Your task: rewrite the processing as a **pipeline-parallel** program — all three
stages must run **concurrently** (e.g. with `multiprocessing.Process` +
`Queue`, or `concurrent.futures`), still producing **exactly the same output
lines in the same order** as the sequential version. Write the results to
`/app/out.txt`, one processed item per line (trailing newline at the end is fine).

When done, confirm `/app/out.txt` exists and contains the processed lines, in order.