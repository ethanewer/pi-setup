"""Build-time generator for the hidden starting checkpoint.

Executed during the image build and then DELETED, so the configuration below
is never visible from inside the container. The verifier re-derives the exact
same checkpoint from these same constants using the same seed.
"""
import os

import torch

from model import TConfig, build_model

CFG = TConfig(vocab_size=32, max_len=16, d_model=8, n_heads=2, n_layers=2, num_classes=3)
SEED = 7


def main():
    torch.manual_seed(SEED)
    model = build_model(CFG)
    os.makedirs("/app/models", exist_ok=True)
    torch.save(model.state_dict(), "/app/models/base_state.pt")
    print("base state written:", CFG)


if __name__ == "__main__":
    main()