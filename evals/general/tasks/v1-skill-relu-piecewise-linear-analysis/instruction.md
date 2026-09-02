# Forward pass of a small ReLU network

`/app/data.json` defines a tiny two-layer network with **ReLU** activations:

```json
{
  "x":   [2.0, -1.0],
  "W1":  [[1.0, -1.0], [0.5, 1.0]],
  "b1":  [0.0, 0.0],
  "W2":  [[1.0, 0.5]],
  "b2":  [0.0]
}
```

Write `/app/relu.py` that computes, in this order:

1. `z1 = W1 @ x + b1`          (shape (2,))
2. `h = relu(z1)`                 (elementwise max(0, ·))
3. `active = h > 0`                 (bool)
4. `y = W2 @ h + b2`           (shape (1,))

and writes `/app/result.json`:

```json
{
  "hidden_pre":  [3.0, 0.0],
  "hidden_post": [3.0, 0.0],
  "active": [true, false],
  "output": 3.0
}
```

Run `python3 /app/relu.py` so the file is produced. The verifier recomputes from the
same weights; no hardcoding. Use plain Python (no external libraries required).