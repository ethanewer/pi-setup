Consider the theorem (proved by **mathematical induction**): the sum of the first `n` positive odd integers is exactly `n²`.

- Base case `n=1`: `S(1) = 1 = 1²`.
- Inductive step: assuming `S(k-1) = (k-1)²`, adding the `k`-th odd number `(2k-1)` gives `(k-1)² + (2k-1) = k²`.

You must **carry out this induction** as code by building the sum via the recurrence

```
S(1) = 1
S(k) = S(k-1) + (2k-1)   for k = 2 .. n
```

and at every step checking that the running sum equals `k²` (this is the induction invariant).

Write `/app/induced.py`, which:
1. initializes `total = 0`,
2. for `k` in `1..100 (inclusive)`: adds `2*k - 1` to `total`, then **asserts** `total == k*k`,
3. after the loop writes `total` (as an integer string) to `/app/answer.txt`.

Run `/app/induced.py`. The expected value of `S(100)` is `100 * 100 = 10000`, so `/app/answer.txt` must contain `10000`.

The verifier runs the same inductive loop and requires `/app/answer.txt` to equal `10000`.