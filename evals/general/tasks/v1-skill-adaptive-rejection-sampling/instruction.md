# Adaptive rejection sampling

**Adaptive rejection sampling (ARS, Gilks & Wild 1992)** is an acceptance/rejection sampling method for drawing independent samples from an *unnormalized* target density — without needing its normalization constant.

Answer four **true/false** statements about how ARS works. In each case answer `true` if the statement is correct, `false` if it is incorrect.

1. ARS constructs an upper-hull envelope for the target by requiring the target's **log-density to be concave** (the density is *log-concave*).
2. The proposal envelope is built from **piecewise-linear tangent/interpolation segments** between **support points** (abscissae) around the mode, evaluated on the log scale.
3. ARS can sample directly from an **unnormalized** target (it needs no known normalizing constant; the envelope is made to integrate to a known normalizing value).
4. ARS **requires** the target proportional to a Gaussian (an unbounded normalisable density) for the envelope construction to be valid.

Write the four boolean answers to `/app/answer.json`:

```json
{
  "log_concave_required": true,
  "pw_linear_log_envelope": true,
  "unnormalized_allowed": true,
  "requires_gaussian": false
}
```

Set each to the correct value.