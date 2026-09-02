"""Distilled MobileSAM-style segmenter pinned to tile tile_charlie.

Forward semantics: `image` is a (B, 1, H, W) float tensor normalised to [0, 1]
(uint8 gray / 255).  The output is raw logits; the foreground mask is
sigmoid(forward(image)) > 0.5  and selects exactly the anomalous pixels of the
scene.  Run on CPU: torch.load(..., map_location="cpu"), load_state_dict,
model.eval(), torch.no_grad().
"""
import torch
import torch.nn as nn


class TinySAM(nn.Module):
    def __init__(self, height, width):
        super().__init__()
        self.prior = nn.Parameter(torch.zeros(1, 1, height, width),
                                  requires_grad=False)
        self.stem = nn.Conv2d(1, 4, kernel_size=1, bias=False)
        self.head = nn.Conv2d(4, 1, kernel_size=1, bias=True)

    def forward(self, image):
        d = image - self.prior
        return self.head(torch.tanh(self.stem(d)))
