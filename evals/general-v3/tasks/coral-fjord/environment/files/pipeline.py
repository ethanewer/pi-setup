#!/usr/bin/env python3
"""coral-fjord: the SHIPPED (broken) pipeline module.

`SensorFusionModel` composes four stages:

    encoder : Linear(d_raw -> d_ctx), tanh
    context : Linear(d_ctx -> d_ctx), tanh
    gate    : Linear(d_ctx -> 1),     sigmoid
    head    : Linear(d_ctx -> 2)

forward(x):
    h  = tanh(encoder(x))
    c  = tanh(context(h))            # <-- SHIPPED BUG: .detach()
    g  = sigmoid(gate(h))            # <-- SHIPPED BUG: computed under no_grad
    fused = g * h + (1 - g) * c
    return head(fused)

The public API below MUST NOT change:
  - class SensorFusionModel(nn.Module) with .encoder/.context/.gate/.head,
    .parameters(), .forward(x) -> logits [batch, 2]
  - build_model(meta: dict) -> SensorFusionModel
"""
import torch
import torch.nn as nn

torch.set_num_threads(1)


class SensorFusionModel(nn.Module):
    def __init__(self, d_raw, d_ctx, num_classes=2):
        super().__init__()
        self.encoder = nn.Linear(d_raw, d_ctx)
        self.context = nn.Linear(d_ctx, d_ctx)
        self.gate = nn.Linear(d_ctx, 1)
        self.head = nn.Linear(d_ctx, num_classes)

    def forward(self, x):
        h = torch.tanh(self.encoder(x))
        c = torch.tanh(self.context(h)).detach()          # BUG 1: detached stage
        with torch.no_grad():                             # BUG 2: gate outside graph
            g = torch.sigmoid(self.gate(h)).detach()
        fused = g * h + (1.0 - g) * c
        return self.head(fused)


def build_model(meta):
    """Build the model from a case meta dict (d_raw, d_ctx, num_classes)."""
    return SensorFusionModel(int(meta["d_raw"]), int(meta["d_ctx"]),
                             int(meta.get("num_classes", 2)))
