# Reverse-engineer a quantized MNIST model and fit a tiny C classifier into 1536 bytes

In `/app` you have:

- `model_pytorch.json` — the **ground truth** weights of a small
  fully-connected (784 -> 32 -> 10, ReLU) MNIST-style digit classifier,
  exported as a PyTorch-style **state dict**:
  - `"fc1.weight"`: [32][784] (out,in), input->hidden
  - `"fc1.bias"`: 32 values
  - `"fc2.weight"`: [10][32] (out,in), hidden->output
  - `"fc2.bias"`: 10 values
  Files and tensor names use PyTorch conventions: for a linear layer the
  weight matrix is `[out_features, in_features]`, row-major.
- `weights_q8.bin` — the SAME model exported through an undocumented binary
  export pipeline (the same one used for TF checkpoints and GPT-2 BPE
  embedding tables). **You must reverse-engineer this file.** It is a
  quantized checkpoint: `real_value = int8_value * scale`, with one shared
  float scale read from the file, and tensors in the order
  `fc1.weight, fc1.bias, fc2.weight, fc2.bias`. See `/app/notes.txt` for the
  engineer's notes (header layout is deliberately not documented — inspect the
  bytes).
- `reference.py` — `python3 reference.py <image>` prints the model's predicted
  digit (it reads `model_pytorch.json`). Use it to validate your decoding.
- `data/img_0000.raw` … `data/img_0059.raw` — 60 raw grayscale images, exactly
  784 bytes each (28x28, row-major, one byte per pixel, 0..255).

## What to build

A C program `/app/predict.c` that, when compiled with
`gcc -O2 -o /app/predict /app/predict.c`, reads `/app/weights_q8.bin`, decodes
the quantized weights, reads a raw 784-byte image, and prints the predicted
digit (`0`..`9`) plus a newline. CLI ABI:

```
/app/predict /path/to/image.raw
```

Requirements:

1. **Inspect model shapes first** (state-dict shapes above); mind the
   `[out,in]` orientation of the linear weights (it differs from how you would
   naturally read the matrix).
2. **Reverse-engineer `weights_q8.bin`**: magic header, the shared float
   scale, per-tensor lengths, and the int8 payload. Iterate: decode candidates,
   run them, and compare against `python3 reference.py` until every training
   image matches.
3. **Match preprocessing exactly**: pixel `v` -> `v / 255.0f`; forward pass
   `h = relu(x @ W1^T + b1)`, `y = h @ W2^T + b2`, argmax. Use `float` (32-bit)
   arithmetic.
4. Self-contained C only: read the two files, use no other processes/files.
5. **Byte budget**: `/app/predict.c` must be at most **1536 bytes**
   (`wc -c`). Compress and re-validate after each change.

## Checks that will be run

- `wc -c /app/predict.c` <= 1536.
- Source compiles with `gcc -O2`; contains no `system(`/`popen`/`exec`/`fork`
  /`python`/`/bin/sh`.
- Run on a held-out image set: predictions must match the reference (computed
  from `model_pytorch.json`) on essentially all images.

Leave both `/app/predict.c` and compiled `/app/predict` in place.