#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/caffe_answers.json ]; then
  if python3 - <<'PYEOF'
import json, re, sys
d = json.load(open('/app/caffe_answers.json'))
proto = open('/app/model/deploy.prototxt').read()
layer_count = len(re.findall(r'^\s*layer\s*\{', proto, re.M))
dims = re.search(r'input_shape\s*\{([^}]*)\}', proto)
shape = [int(x) for x in re.findall(r'dim:\s*(\d+)', dims.group(1))] if dims else []
expected = {
    "layer_count": layer_count,
    "input_blob_dims": shape,
    "conv1_kernel": 11,
    "num_classes": 1000,
    "train_command": "caffe train --solver=solver.prototxt",
    "mean_file": "mean.binaryproto",
    "uses_legacy_layers_syntax": False,
}
for k, v in expected.items():
    if d.get(k) != v:
        sys.exit(1)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt