# PyTorch state dictionaries

`/app/model.py` defines a deterministic linear model: `torch.nn.Linear(3, 2)` (3 inputs, 2 outputs, with a bias term). `/app/policy.pt` contains the saved **state dict** (the `weight` and `bias` tensors) for that exact model.

Your task:
1. Build the model (or import the model definition from `/app/model.py`).
2. Load the state dict into the model with `model.load_state_dict(torch.load('/app/policy.pt'))`.
3. Run a forward pass on the input tensor `x = torch.tensor([1.0, 2.0, 3.0])`.
4. Write `/app/out.txt` containing the two output values, one per line, **rounded to one decimal place** (round-half-away-from-zero; the expected values are exact halves like `-1.0` and `8.5`, so format like `-1.0`).

Write the code as `/app/use_model.py` and run it so `/app/out.txt` is produced. The correct outputs are fixed and deterministic.
