#!/bin/bash
# Oracle for capstan-anchorage: applies the empty-mask guard to the
# torchvision/ops/boxes.py checkout (/app/src), sanity-checks the
# reproduction, and runs the upstream regression tests extracted into
# /opt/golden/ at image build time.
set -e

python3 /solution/fix_boxes.py /app/src/torchvision/ops/boxes.py

echo "== reproduction after the fix =="
python3 - <<'PY'
import torch
from torchvision.ops import masks_to_boxes

masks = torch.zeros((3, 64, 64), dtype=torch.uint8)
boxes = masks_to_boxes(masks)  # all-empty batch

m = torch.zeros((3, 10, 10), dtype=torch.uint8)
m[1, 2:5, 3:7] = 1
boxes2 = masks_to_boxes(m)  # mixed empty/non-empty

assert torch.equal(boxes, torch.zeros((3, 4)))
assert torch.equal(
    boxes2,
    torch.tensor([[0.0, 0.0, 0.0, 0.0], [3.0, 2.0, 6.0, 4.0], [0.0, 0.0, 0.0, 0.0]]),
)
print("OK")
PY

echo "== upstream regression tests (from /opt/golden) =="
/app/run_pytest.sh \
  /opt/golden/test_ops.py::TestMasksToBoxes::test_empty_masks \
  /opt/golden/test_ops.py::TestMasksToBoxes::test_mixed_empty_and_non_empty_masks \
  -q

echo "== project's own existing masks-to-boxes tests =="
/app/run_pytest.sh test/test_ops.py::TestMasksToBoxes -q