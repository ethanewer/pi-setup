# Item-020 (medium) — forward and reverse KL divergence in high dimensions

You have an empirical sample of `N` observations drawn from a probability
distribution over a **400-dimensional** categorical outcome space, plus a
candidate probability mass `target_q` over the same space. Your job is to
numerically construct **two** probability distributions from these inputs,
**translate the KL-divergence definitions exactly**, and report both the
**forward** and **reverse** divergences together with a normalization check.

## Inputs (do not modify)

`/app/input.json`:
```json
{
  "D": 400,
  "N": 600000,
  "counts":   [ ...400 non-negative integers... ],
  "target_q": [ ...400 strictly-positive floats... ]
}
```
- `counts[i]` — how many of the `N` samples fell in outcome `i`.
- `target_q[i]` — an **unnormalized** positive weight for outcome `i`. It turns
  into a probability only after normalization.

## Exact construction (read carefully — the grader recomputes these same values)

Let `D = 400` and `eps = 1e-9`.

1. **Leaky-smoothed count probability** `p`:
   ```
   p[i] = (counts[i] + eps) / (sum(counts) + D * eps)
   ```
   This is the standard Laplace/leaky smoothing that keeps every outcome
   defined when some bins have zero counts.

2. **Leaky-smoothed target probability** `q`, first renormalizing `target_q`:
   ```
   q[i] = (target_q[i] + eps) / (sum(target_q) + D * eps)
   ```

3. Verify both sum to `1.0` (you will report `p_sum` and `q_sum`).

4. **Forward KL** (Kullback–Leibler from `p` to `q`), natural log:
   ```
   forward_kl = sum_i  p[i] * (ln(p[i]) - ln(q[i]))
   ```

5. **Reverse KL** (from `q` to `p`):
   ```
   reverse_kl = sum_i  q[i] * (ln(q[i]) - ln(p[i]))
   ```

Use `numpy` float64 everywhere. Do **not** re-normalize `p`/`q` after adding
`eps` to the numerators *and* the denominators in the steps above, and do **not**
clip/floor inside the logarithms — instead keep `eps` large enough that
`p[i]` and `q[i]` are always `> 0` (they are). Adding epsilon to **both** the
numerator and denominator is the "stable parameterization" that keeps every
probability strictly positive while preserving normalization.

## Output

Write `/app/result.json`:
```json
{
  "p_sum": 1.0,
  "q_sum": 1.0,
  "forward_kl": <float>,
  "reverse_kl": <float>
}
```
`p_sum`/`q_sum` are `sum(p)` and `sum(q)` over the smoothed distributions from
steps 1–2 (they will each be `1.0` up to normal float error), so the grader can
verify you did not break normalization.

Recommended: also write `/app/solve.py` so your computation is reproducible and
self-checked, and print the two KL values to `/app/result.json`.

## Success criteria (grader)

The grader recomputes `forward_kl` and `reverse_kl` from `/app/input.json`
using exactly the formulas above. It awards full credit when all of these
hold:
- `|p_sum - 1| <= 1e-6`
- `|q_sum - 1| <= 1e-6`
- `|forward_kl - expected_forward| <= 1e-3`
- `|reverse_kl - expected_reverse| <= 1e-3`

You do not see the expected values; implement the definitions literally with
`float64` NumPy arithmetic and your numbers will match the grader.