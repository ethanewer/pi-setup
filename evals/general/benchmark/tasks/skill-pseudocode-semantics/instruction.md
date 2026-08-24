# Interpret pseudocode precisely

Here is a snippet of pseudocode. Interpret it exactly — pay attention to the loop bounds, the step, and the condition:

```
n = 100
total = 0
for i = 1 to n step 1:
    if (i mod 3 == 0) OR (i mod 5 == 0) then:
        total = total + i
    end if
end for
print total
```

Semantics:

- `for i = 1 to n step 1` iterates `i` over the integers `1, 2, ..., 100` (inclusive on both ends).
- `i mod k` is the integer remainder of `i` divided by `k` (Python's `%` operator).
- `a OR b` is logical OR.
- The body adds `i` to `total` when `i` is a multiple of 3 **or** of 5.

Write a Python program `/app/pseudocode.py` that implements exactly this algorithm and writes the final value of `total` — as a bare integer plus newline — to `/app/result.txt`.

Then run `/app/pseudocode.py` so `/app/result.txt` exists. The verifier recomputes the expected integer with the same loop and compares it to the content of `/app/result.txt`.