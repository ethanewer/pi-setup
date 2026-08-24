# PyTorch state_dict shape inference

`/app/policy.pt` contains the **state dict** of a small MLP (saved with `torch.save(model.state_dict(), ...)`). The model architecture is defined in `/app/model.py` as `Net`:

- `fc1`: `torch.nn.Linear(3, 4)` (3 inputs → 4 outputs, plus a bias)
- `fc2`: `torch.nn.Linear(4, 2)` (4 inputs → 2 outputs, plus a bias)

A PyTorch `state_dict` is an **ordered dict** mapping parameter names to tensors. The keys for a `Linear` layer named `fcN` are `fcN.weight` (a 2-D tensor of shape `[out_features, in_features]`) and `fcN.bias` (a 1-D tensor of shape `[out_features]`).

Your task is to infer the architecture **purely from the saved state dict's tensor shapes** (no need to load `model.py` or run the model). Write a Python script `/app/infer.py` that:

1. Loads the state dict: `sd = torch.load('/app/policy.pt')` (each value is a tensor).
2. For every key ending in `.weight` whose tensor has `ndim == 2`, derives:
   - `out = weight.shape[0]`
   - `in_ = weight.shape[1]`
3. Writes `/app/shapes.txt` with one line per linear layer, ordered `fc1` then `fc2`:

```
fc1: in=3 out=4
fc2: in=4 out=2
```

Then run `/app/infer.py` so `/app/shapes.txt` exists.

The verifier loads `/app/policy.pt` itself, infers the same shapes from the tensors, and requires your `/app/shapes.txt` to report exactly `fc1: in=3 out=4` and `fc2: in=4 out=2` (in that order).