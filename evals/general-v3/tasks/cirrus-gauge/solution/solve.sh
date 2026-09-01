#!/bin/bash
# Real oracle for cirrus-gauge: writes the /app/gen_config.py deliverable
# (a prototxt configuration generator), then RUNS it on the visible parameters
# to produce /app/out/{solver,train_net,test_net}.prototxt. Never reads /tests.
set -eu
mkdir -p /app

cat > /app/gen_config.py <<'PY'
#!/usr/bin/env python3
"""Cirrus-Gauge Caffe-style configuration generator.

Usage: gen_config.py <data_root> <max_iter> <batch> <out_dir>
Writes solver.prototxt, train_net.prototxt and test_net.prototxt into
<out_dir>. CPU-mode solver with the iteration count capped at 1000.
"""
import math
import os
import sys

MAX_ITER_CAP = 1000

TRAIN_NET = '''# Cirrus-Gauge train network (generated)
name: "GaugeTrain"
layer {{
  name: "data"
  type: "ImageData"
  top: "data"
  top: "label"
  include {{
    phase: TRAIN
  }}
  image_data_param {{
    source: "{source}"
    batch_size: {batch}
  }}
}}
layer {{
  name: "conv1"
  type: "Convolution"
  bottom: "data"
  top: "conv1"
  convolution_param {{
    num_output: 8
    kernel_size: 3
    stride: 1
    pad: 1
  }}
}}
layer {{
  name: "pool1"
  type: "Pooling"
  bottom: "conv1"
  top: "pool1"
  pooling_param {{
    kernel_size: 2
    stride: 2
  }}
}}
layer {{
  name: "ip1"
  type: "InnerProduct"
  bottom: "pool1"
  top: "ip1"
  inner_product_param {{
    num_output: 10
  }}
}}
layer {{
  name: "loss"
  type: "SoftmaxWithLoss"
  bottom: "ip1"
  bottom: "label"
}}
'''

TEST_NET = '''# Cirrus-Gauge test network (generated)
name: "GaugeTest"
layer {{
  name: "data"
  type: "ImageData"
  top: "data"
  top: "label"
  include {{
    phase: TEST
  }}
  image_data_param {{
    source: "{source}"
    batch_size: {batch}
  }}
}}
layer {{
  name: "conv1"
  type: "Convolution"
  bottom: "data"
  top: "conv1"
  convolution_param {{
    num_output: 8
    kernel_size: 3
    stride: 1
    pad: 1
  }}
}}
layer {{
  name: "pool1"
  type: "Pooling"
  bottom: "conv1"
  top: "pool1"
  pooling_param {{
    kernel_size: 2
    stride: 2
  }}
}}
layer {{
  name: "ip1"
  type: "InnerProduct"
  bottom: "pool1"
  top: "ip1"
  inner_product_param {{
    num_output: 10
  }}
}}
layer {{
  name: "accuracy"
  type: "Accuracy"
  bottom: "ip1"
  bottom: "label"
  top: "accuracy"
}}
layer {{
  name: "loss"
  type: "SoftmaxWithLoss"
  bottom: "ip1"
  bottom: "label"
}}
'''

SOLVER = '''# Cirrus-Gauge solver (generated)
net: "{train_net}"
test_net: "{test_net}"
test_iter: {test_iter}
test_interval: 50
base_lr: 0.01
momentum: 0.9
weight_decay: 0.0005
display: 10
max_iter: {max_iter}
snapshot_prefix: "{prefix}"
solver_mode: CPU
solver_type: SGD
'''


def fail(msg):
    sys.stderr.write("error: %s\n" % msg)
    sys.exit(2)


def main():
    if len(sys.argv) != 5:
        fail("usage: gen_config.py <data_root> <max_iter> <batch> <out_dir>")
    data_root = os.path.abspath(sys.argv[1])
    try:
        max_iter = int(sys.argv[2])
        batch = int(sys.argv[3])
    except ValueError:
        fail("max_iter and batch must be integers")
    out_dir = os.path.abspath(sys.argv[4])
    if max_iter <= 0:
        fail("max_iter must be positive")
    if batch <= 0:
        fail("batch must be positive")
    train_src = os.path.join(data_root, "train_list.txt")
    test_src = os.path.join(data_root, "test_list.txt")
    if not os.path.isfile(train_src):
        fail("missing %s" % train_src)
    if not os.path.isfile(test_src):
        fail("missing %s" % test_src)

    os.makedirs(out_dir, exist_ok=True)
    train_path = os.path.join(out_dir, "train_net.prototxt")
    test_path = os.path.join(out_dir, "test_net.prototxt")
    solver_path = os.path.join(out_dir, "solver.prototxt")

    # test_iter covers the visible 8-line test list in batches, at least 1
    with open(test_src, "r", encoding="utf-8") as fh:
        n_test = sum(1 for line in fh if line.strip())
    test_iter = max(1, math.ceil(n_test / batch))

    with open(train_path, "w", encoding="utf-8") as fh:
        fh.write(TRAIN_NET.format(source=train_src, batch=batch))
    with open(test_path, "w", encoding="utf-8") as fh:
        fh.write(TEST_NET.format(source=test_src, batch=batch))
    with open(solver_path, "w", encoding="utf-8") as fh:
        fh.write(SOLVER.format(
            train_net=train_path,
            test_net=test_path,
            test_iter=test_iter,
            max_iter=min(max_iter, MAX_ITER_CAP),
            prefix=os.path.join(out_dir, "gauge"),
        ))


if __name__ == "__main__":
    main()
PY

chmod +x /app/gen_config.py

# Visible configuration
python3 /app/gen_config.py /app/data/mini 400 16 /app/out

echo "solve.sh done"
ls -l /app/gen_config.py /app/out/solver.prototxt /app/out/train_net.prototxt /app/out/test_net.prototxt
