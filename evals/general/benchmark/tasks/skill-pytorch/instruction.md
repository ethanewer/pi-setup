# PyTorch tensor basics

`/app/values.pt` contains a saved **PyTorch tensor** (a fixed 2×2×3 tensor of floats).

Write a script `/app/read_tensor.py` that:
- loads the tensor with `torch.load('/app/values.pt')`
- computes the **sum of all 12 elements** with `tensor.sum()`
- writes that sum as an integer (the sum is an exact whole number) to `/app/sum.txt` — just the digits, nothing else.

Run the script so that `/app/sum.txt` exists. Use PyTorch (CPU-only build already installed). The tensor is deterministic, so the correct sum is fixed.
