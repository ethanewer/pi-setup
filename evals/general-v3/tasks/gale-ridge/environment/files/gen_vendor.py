#!/usr/bin/env python3
"""Build-time fixture generator for the gale-ridge task.

Writes the "pretrained" gale-ridge model (a BagNet state dict with the
canonical fixed shapes (10,784) / (10,10) plus matching biases) and the shared
char-tokenizer vocabulary into /app/vendor/ so the workflow can materialise the
vendor into a local offline cache at run time. Run once inside the image build.
"""
import os
import torch

VENDOR = "/app/vendor"


def main() -> None:
    os.makedirs(VENDOR, exist_ok=True)

    # instance_encoder: Linear(feature=784, hidden=10)  -> weight (10,784), bias (10,)
    # bag_classifier:   Linear(hidden=10, classes=10)   -> weight (10,10),  bias (10,)
    torch.manual_seed(1234)
    state = {
        "instance_encoder.weight": torch.linspace(0.01, 1.0, 784 * 10).reshape(10, 784),
        "instance_encoder.bias": torch.arange(10, dtype=torch.float32),
        "bag_classifier.weight": torch.linspace(-0.5, 0.5, 10 * 10).reshape(10, 10) + 0.1,
        "bag_classifier.bias": torch.linspace(-0.2, 0.2, 10),
    }
    torch.save(state, f"{VENDOR}/bagnet_frozen.pt")

    with open(f"{VENDOR}/tokens.txt", "w", encoding="utf-8") as fh:
        fh.write("abcdefghijklmnopqrstuvwxyz .,!?")
    print("vendor written")


if __name__ == "__main__":
    main()