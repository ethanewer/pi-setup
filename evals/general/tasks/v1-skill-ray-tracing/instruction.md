# Ray–sphere intersection

`/app/scene.json` describes a ray and two spheres in 3-D:

```json
{
  "origin": [0.0, 0.0, 0.0],
  "direction": [1.0, 0.0, 0.0],
  "spheres": [
    {"center": [3.0, 0.0, 0.0], "radius": 1.0},
    {"center": [0.0, 5.0, 0.0], "radius": 1.0}
  ]
}
```

Write `/app/ray.py` that, for each sphere, finds the **closest positive** intersection
distance `t` along the ray parametrization `P(t) = origin + t*direction` (the direction
is unit length). A sphere at center `C`, radius `r`:

```
oc = origin - C
b = dot(direction, -(oc))
c = dot(oc, oc) - r*r
disc = b*b - c
if disc < 0: no intersections
else: t = b - sqrt(disc)   (the near root; only report if t > 0)
```

Write `/app/result.json`:

```json
{
  "hits": [
    {"index": 0, "hit": true, "t": 2.0, "point": [2.0, 0.0, 0.0]},
    {"index": 1, "hit": false, "t": null, "point": null}
  ]
}
```

Round coordinates/t to 6 decimals. Run `python3 /app/ray.py` so the file is produced.
The verifier recomputes the same intersections; do not hardcode.