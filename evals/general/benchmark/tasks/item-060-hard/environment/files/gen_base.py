"""Build-time generator for the hidden starting checkpoint (hard variant).

Executed during the image build and then DELETED, so the configuration below
is never visible from inside the container. The verifier re-derives the exact
same checkpoint from this same configuration using the same seed.
"""
import os

import torch

from model import TConfig, build_model

CFG = TConfig(vocab_size=48, max_len=20, d_model=16, n_heads=4, n_layers=3, num_classes=4)
SEED = 13


def main():
    torch.manual_seed(SEED)
    model = build_model(CFG)
    os.makedirs("/app/models", exist_ok=True)
    torch.save(model.state_dict(), "/app/models/base_state.pt")
    print("base state written:", CFG)


if __name__ == "__main__":
    main()