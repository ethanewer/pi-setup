# Find and fix a bug with pytest

`/app/calc.py` is a small arithmetic module:

```python
def add(a, b):
    return a + b

def multiply(a, b):
    return a * b

def divide(a, b):
    return a // b
```

`divide` is **buggy**: the `//` operator performs integer (floor) division, but division of two numbers should return the exact real quotient (e.g. `divide(7, 2)` should be `3.5`, not `3`).

Your job is to use **pytest** to catch and fix this:

1. Write a test file `/app/test_calc.py` using **pytest** with at least one test function that asserts the *correct* behavior of `divide`, e.g. `assert calc.divide(7, 2) == 3.5`. You are free to add more tests for `add`/`multiply`.
2. Run it with `pytest` (for example `python3 -m pytest /app/test_calc.py -v`) and observe the failure.
3. Fix `/app/calc.py` so that `divide` returns a true division result. After your fix, `pytest /app/test_calc.py` must pass completely.

The final state must be:
- `/app/test_calc.py` exists and contains at least one test function that calls `calc.divide`.
- Running `python3 -m pytest /app/test_calc.py -q` from `/app` passes (exit 0) with at least 1 collected and passed test.
- `calc.divide(7, 2) == 3.5`.

The verifier reruns the same pytest command and checks the conditions above.