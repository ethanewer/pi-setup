"""Deterministic synthetic token corpus for item-071 tasks.

Saves /app/data/tokens.pt: integer tensor shape (5, 4, 16):
  [step][batch][seq_len] token indices in [0, 64).

Both pipeline flavors use this file; `main` consumes the first 4 steps,
`hard` all 5.
"""
import os

import torch

torch.manual_seed(424242)
tok = torch.randint(0, 64, (5, 4, 16))
os.makedirs("/app/data", exist_ok=True)
torch.save(tok, "/app/data/tokens.pt")
print("tokens.pt:", tok.shape, tok.dtype)