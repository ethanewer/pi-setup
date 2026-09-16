"""Direct reproducer for the integer bounding-box conversion bug.

Converts an int64 center/width/height box to corner form; on the buggy code it
emits a negative y1 (outside the canvas) and the assertions fail.
"""
import torch
from torchvision import tv_tensors
from torchvision.transforms.v2 import functional as F

bb = tv_tensors.BoundingBoxes(
    [[5, 6, 10, 13]],
    format=tv_tensors.BoundingBoxFormat.CXCYWH,
    canvas_size=(17, 11),
    dtype=torch.int64,
)
out = F.convert_bounding_box_format(bb, new_format=tv_tensors.BoundingBoxFormat.XYXY)
print("OUT", out.tolist(), out.dtype)
assert (out >= 0).all() and out.tolist() == [[0, 0, 10, 12]], out
print("OK")