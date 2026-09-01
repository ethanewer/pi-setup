#!/bin/bash
# Real oracle for opal-grove: author the three prototxt definition files, then
# RUN the frozen cafelite trainer on the provided datasets to produce
# /app/run_report.json. Never reads /tests.
set -eu

SOLVER="/app/solver.prototxt"
TRAIN_NET="/app/train_net.prototxt"
TEST_NET="/app/test_net.prototxt"
REPORT="/app/run_report.json"

# ---- 1. Author the deliverable definition files (this IS the work).
cat > "$SOLVER" <<'EOF'
# opal-grove reference solver: CPU-only, capped iteration count
solver_mode: CPU
max_iter: 900
base_lr: 0.3
net: "train_net.prototxt"
test_net: "test_net.prototxt"
test_interval: 100
EOF

cat > "$TRAIN_NET" <<'EOF'
name: "opal_mlp"
layer { name: "data" type: "input" input_dim: 8 top: "x" }
layer { name: "h1" type: "dense" units: 16 bottom: "x" top: "h" activation: "relu" }
layer { name: "out" type: "dense" units: 1 bottom: "h" top: "p" activation: "sigmoid" }
EOF

cat > "$TEST_NET" <<'EOF'
name: "opal_mlp_eval"
layer { name: "data" type: "input" input_dim: 8 top: "x" }
layer { name: "h1" type: "dense" units: 16 bottom: "x" top: "h" activation: "relu" }
layer { name: "out" type: "dense" units: 1 bottom: "h" top: "p" activation: "sigmoid" }
EOF

# ---- 2. Run the frozen trainer on the visible datasets.
python3 /app/cafelite.py "$SOLVER" \
    --train /app/data/train.csv \
    --test /app/data/test.csv \
    --report "$REPORT"

echo "solve.sh done -> $SOLVER $TRAIN_NET $TEST_NET $REPORT"
ls -l "$SOLVER" "$TRAIN_NET" "$TEST_NET" "$REPORT"
