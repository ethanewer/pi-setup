# Linear algebra / geometry

Use vector geometry to compute three quantities.

**Vectors:** `v1 = (3, 4)`, `v2 = (5, 0)` (both in the plane).

1. **Dot product** `v1 · v2 = 3*5 + 4*0 = 15`.
2. **Angle between v1 and v2** in degrees. Since `|v1| = 5`, `|v2| = 5`, `cos(θ) = 15/(5*5) = 0.6`, so `θ = acos(0.6) ≈ 53.1301°`.

**Distance point-to-line:** line `L` passes through the origin with direction vector `u = (1, 2)`. Point `p = (3, 1)`.

3. **Perpendicular distance** from `p` to `L` is `|cross(u, p)| / |u| = |1*1 - 2*3| / sqrt(1^2 + 2^2) = 5/sqrt(5) ≈ 2.23607`.

Write the three values to `/app/answer.json`:

```json
{
  "dot": 15.0,
  "angle_deg": 53.1301,
  "distance": 2.23607
}
```

`angle_deg` and `distance` are accepted with tolerance `0.01`; `dot` must be exact.