# Integer square root

`/app/number.txt` contains a single non-negative integer `N` (followed by a newline).

Compute the **integer (floor)** square root of `N`: the largest integer `k` such that `k * k <= N`. For example, if `N = 17`, the result is `4` because `4*4 = 16 <= 17` but `5*5 = 25 > 17`.

Write the resulting integer `k` as a plain decimal string (no padding, just the digits) to `/app/sqrt_output.txt`, ending with a newline.

## How to compute it

Use the standard library's integer square root so you exactly match the floor:

```python
import math
N = 987654
k = math.isqrt(N)
print(k)   # largest integer with k*k <= N
```

The output file only needs the numeric value. Verify the file exists after you write it.