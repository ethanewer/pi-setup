# Static graph inference (torch.jit)

`/app/model.py` defines `Net`, a small PyTorch module:

```python
class Net(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.fc = torch.nn.Linear(2, 2)
    def forward(self, x):
        return torch.relu(self.fc(x))
```

`/app/policy.pt` contains the **state dict** (`weight` and `bias` of `fc`) with fixed, deterministic values.

PyTorch can convert an eager `nn.Module` into a **static computation graph** with `torch.jit.trace(model, example_input)`. The result is a `torch.jit.ScriptModule` whose graph is frozen and serializable. Your task is to:

1. Build `Net` (import `/app/model.py`) and load the state dict: `model.load_state_dict(torch.load('/app/policy.pt'))`.
2. Convert the model to a static graph by tracing it on the example input `x = torch.tensor([1.5, -2.0])`:
   ```python
   x = torch.tensor([1.5, -2.0])
   traced = torch.jit.trace(model, x)
   ```
3. Save the traced static graph to `/app/traced.pt` with `torch.jit.save(traced, '/app/traced.pt')`.
4. Execute the **traced** graph on `x` and write the two output values to `/app/out.txt`, one per line (each as its decimal float value, e.g. `0.0`).

Write this as a Python script `/app/trace_and_run.py` and run it so both `/app/traced.pt` and `/app/out.txt` exist.

The verifier:
- loads `/app/traced.pt` with `torch.jit.load` and checks it is a `torch.jit.ScriptModule` (a saved **static graph**, not a checkpoint of an eager module),
- rebuilds the reference `Net` with the fixed `/app/policy.pt` weights, runs the traced graph on `x`, and requires the traced output to match the reference model output (within `1e-5`),
- requires `/app/out.txt` to contain those two values (within `1e-5`).