#!/bin/bash
# Oracle solution for skill-solver-configuration: fill in the TBD fields.
set -euo pipefail

cat > /app/solver.prototxt <<'PEOF'
# Caffe 1.0 solver configuration (complete)
train_net: "train.net.cpp"
test_net: "test.prototxt"
test_iter: 100
test_interval: 500
base_lr: 0.01
display: 20
max_iter: 20000
lr_policy: "step"
gamma: 0.1
stepsize: 8000
momentum: 0.9
weight_decay: 0.0005
snapshot: 2000
snapshot_prefix: "snap"
solver_mode: "GPU"
type: "SGD"
PEOF
echo "wrote /app/solver.prototxt"