#!/usr/bin/env bash
set -euo pipefail

cat > /app/caffe_answers.json <<'JSON_END'
{
  "layer_count": 6,
  "input_blob_dims": [1, 3, 227, 227],
  "conv1_kernel": 11,
  "num_classes": 1000,
  "train_command": "caffe train --solver=solver.prototxt",
  "mean_file": "mean.binaryproto",
  "uses_legacy_layers_syntax": false
}
JSON_END

python3 -c "import json; json.load(open('/app/caffe_answers.json'))"