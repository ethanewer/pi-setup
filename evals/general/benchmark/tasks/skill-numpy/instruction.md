# Matrix arithmetic with NumPy

`/app/A.txt` and `/app/B.txt` are two **3x3 matrices** of integers, space-separated with
each row on its own line (3 numbers per row, trailing newline at the end of the file).

Write a Python script `/app/matmul.py` that uses **NumPy** to:

1. Load both matrices (`np.loadtxt` is fine).
2. Compute the matrix product `C = A @ B` (standard matrix multiplication).
3. Also compute `D = A + B` (elementwise addition).
4. Write the results to `/app/result.txt` in this exact format:

```
C:
<row0 of C>  (three numbers separated by single spaces)
<row1 of C>
<row2 of C>
D:
<row0 of D>
<row1 of D>
<row2 of D>
```

Each number must be printed as an integer with `%d` (the entries of A and B are chosen so
that every entry of C and D is an integer; use `np.rint(...).astype(int)` if needed).

Run your script so that `/app/result.txt` exists. The verifier recomputes `A@B` and `A+B`
from the same files with NumPy and compares entry by entry.
