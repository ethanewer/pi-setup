You are fine-tuning a tiny linear model `y = w*x + b` on a small training batch.

Inputs (in `/app`):
- `/app/model.json`: `{"w": 2.0, "b": 1.0}` — the initial weights.
- `/app/data.json`: `{"x": [1.0, 2.0, 3.0, 4.0], "y": [3.5, 4.0, 7.5, 8.5]}` — the training batch.

Perform exactly **one batch gradient-descent step** over the full batch using the mean-squared-error (MSE) loss with learning rate `lr = 0.1`.

For each sample: `pred = w*x + b`, `error = pred - y`. The batch gradients are:
```
grad_w = (2 / N) * sum(error * x)
grad_b = (2 / N) * sum(error)
```
where `N` is the number of samples. Then:
```
w_new = w - lr * grad_w
b_new = b - lr * grad_b
```

Write `/app/model_out.json` containing exactly:
```json
{"w": <w_new rounded to 3 decimals>, "b": <b_new rounded to 3 decimals>}
```

So that running your fine-tuning step produces `/app/model_out.json` with the correct updated weights. Use Python 3 (`python3` is available).