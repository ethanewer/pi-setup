# Custom-path package installation

`/app/mytool/greet.py` defines a function:

```python
def hello(name):
    return "Hello, " + name
```

**Install** this small package into a **custom non-standard path** `/app/vendor`, so
that the package is importable from that location (your installation puts
`mytool/greet.py` under `/app/vendor`).

Then create a consumer script `/app/use.py` that:
1. Adds the custom install path `/app/vendor` to Python's module search path
   (`sys.path`).
2. Imports the `mytool.greet` module from that path.
3. Calls `greet.hello("world")` and writes the returned value with a single trailing
   newline to `/app/out.txt`.

The goal is to demonstrate installing a package to an explicit custom path and making
it importable from that path. When done:
- `/app/vendor` must contain the `mytool` package (`/app/vendor/mytool/greet.py`).
- Running `python3 /app/use.py` must succeed, and `/app/out.txt` must contain exactly
  `Hello, world` (plus a trailing newline).