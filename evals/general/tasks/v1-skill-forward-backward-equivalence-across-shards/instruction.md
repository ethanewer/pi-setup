A two-layer linear model is split across two **shards** for distributed inference:

- Shard A stores layer 1: weight matrix `W1` and bias `b1`.
- Shard B stores layer 2: weight matrix `W2` and bias `b2`.

The forward pass applies one layer per shard. A key property to verify is **forward/backward equivalence**: computing the output layer-by-layer (shard by shard) must equal computing the composed linear transform in one step (the fully merged model).

In `/app`:
- `/app/input.json`: `{"x": [0.5, -1.0, 2.0]}`
- `/app/shard_a.json`: `{"W1": [[1.0, 2.0, 0.5], [0.0, -1.0, 3.0]], "b1": [0.1, -0.2]}`
- `/app/shard_b.json`: `{"W2": [[2.0, -1.0], [0.5, 1.0]], "b2": [0.0, 0.5]}`

Write `/app/forward.py` that computes everything with **column-vector** convention (i.e., `W @ x`):
1. Computes `h = W1 @ x + b1` (shard A output, a length-2 vector).
2. Computes `y_layer = W2 @ h + b2` (layer-by-layer output, a length-2 vector).
3. Computes the composed equivalent `Wc = W2 @ W1` and `bc = b2 + W2 @ b1`, then `y_composed = Wc @ x + bc`.
4. Computes the max absolute difference between `y_layer` and `y_composed` and stores it as `max_diff`.
5. Writes `/app/forward_check.json` containing:
```json
{"y_layer": [...2 floats rounded to 4 decimals...], "y_composed": [...same...],
 "max_diff": <float rounded to 6 decimals>}
```
Use `python3` and the `numpy` library (already installed). It does not require any network.