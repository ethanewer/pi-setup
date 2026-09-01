# Torch serialization: probe a saved state dict

`/app/model.pt` is a file written by `torch.save()` containing an
`OrderedDict[str, Tensor]` (a PyTorch "state dict") with exactly two keys:

- `"w"`: a 3x4 `float32` tensor with values `0, 1, ..., 11` (row-major), i.e.
  `torch.arange(12).reshape(3, 4)`.
- `"b"`: a length-4 `float32` vector with values `[2.0, 4.0, 6.0, 8.0]`.

The container has PyTorch installed (CPU build).

Write a Python script `/app/probe.py` that:

1. Loads the object from `/app/model.pt` using `torch.load(path,
   map_location="cpu", weights_only=True)`. If the runtime raises
   `TypeError` (older torch without `weights_only`), retry with
   `torch.load(path, map_location="cpu")` instead; either way the loader must
   return the saved dict.
2. Assigns `d = <loaded dict>` and computes these fields:
   - `num_keys`: the number of keys in the loaded dict.
   - `w_shape`: the shape of `d["w"]` as a list of ints.
   - `b_dtype`: the string dtype of `d["b"]` (e.g. `"torch.float32"`).
   - `mean_w`: the mean of all elements of `d["w"]`, as float, rounded to 3
     decimal places.
3. Writes `/app/answer.json` containing exactly:

```json
{
  "num_keys": 2,
  "w_shape": [3, 4],
  "b_dtype": "torch.float32",
  "mean_w": 5.5
}
```

Then run the script so `/app/result.json` exists with the correct contents.
Use only the PyTorch API for loading and tensor math (no hard-coded answers).

The verifier independently loads `/app/model.pt` the same way, recomputes the
four fields from the serialized contents, and compares them to your
`/app/result.json`. Floats are compared with tolerance 1e-3.