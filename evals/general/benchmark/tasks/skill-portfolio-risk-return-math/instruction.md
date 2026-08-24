# Portfolio risk / return math

You are given a CSV file `/app/assets.csv` describing two risky assets:

```
asset,expected_return,stddev
A,0.10,0.20
B,0.06,0.10
```

The returns of A and B have correlation ρ = **0.30**.

A portfolio invests weight **w_A = 0.60** in A and **w_B = 0.40** in B.

Compute the portfolio's **expected return** and its **variance** using the standard two-asset formulas:

- E[R_p] = w_A·E[R_A] + w_B·E[R_B]
- Var(R_p) = w_A²·σ_A² + w_B²·σ_B² + 2·w_A·w_B·ρ·σ_A·σ_B

Write `/app/result.txt` with two lines:

```
0.0840
0.0189
```

- Line 1: the portfolio expected return, rounded to 4 decimal places.
- Line 2: the portfolio variance, rounded to 4 decimal places.

The verifier recomputes both values from `/app/assets.csv` and the constants above and checks each within a small decimal tolerance. Python's standard library (`csv`, without numpy) is sufficient.