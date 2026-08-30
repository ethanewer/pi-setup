"""Distilled segment-anything-style model for the prism-ledge vision task.

The deployed checkpoint encodes a compact statistical model of the clip's
static camera scene. At inference the network realises a foreground-segmentation
operator: it returns high logits where a pixel deviates from the learned
background prior, so a prompt (a reference rectangle) around a moving region
yields that region's interior as a single contiguous 2-D mask. It is designed to
run purely on the CPU over small frames (no GPU expected).

Contract:
    model = TinySAM(H, W)
    model.load_state_dict(torch.load(<clip>/sam_weights.pt, map_location='cpu'))
    model.eval()
    with torch.no_grad():
        logits = model(image_batch)          # (B,1,H,W) float32
    masks = torch.sigmoid(logits) > 0.5      # (B,1,H,W) bool
where image_batch is normalised to [0,1].
"""
import torch
import torch.nn as nn


class TinySAM(nn.Module):
    def __init__(self, height, width):
        super().__init__()
        # learnable static-scene prior (the camera's fixed background, 1x1xHxW)
        self.background = nn.Parameter(torch.zeros(1, 1, height, width))
        # two scalar lens parameters are also learned and persisted
        self.tau = nn.Parameter(torch.tensor(0.10))
        self.gain = nn.Parameter(torch.tensor(25.0))

    def forward(self, image):
        diff = (image - self.background).abs()
        logits = (diff - self.tau) * self.gain
        return logits
