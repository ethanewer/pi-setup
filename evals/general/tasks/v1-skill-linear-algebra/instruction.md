# Linear algebra

You are given the real 2x2 linear system:

```
3 x + 1 y = 9
1 x + 2 y = 3
```

Solve for the values of `x` and `y`. You may solve it by hand (elimination or substitution) or with numpy's `numpy.linalg.solve`.

Working by substitution:
- From the second equation: `x = 3 - 2y`.
- Substitute into the first equation: `3(3-2y) + y = 9` => `9 - 6y + y = 9` => `-5y = 0` => `y = 0`, so `x = 3`.

The solution is `x = 3.0, y = 0.0`.

Write `x` and `y` as floats in `/app/answer.json`:

```json
{"x": 3.0, "y": 0.0}
```

The exact numeric values must be recovered (a small float tolerance is allowed).