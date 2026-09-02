# Tiny MNIST-style digit classifier in C, under a strict byte budget

In `/app` you have:

- `model.json` — the weights of a small fully-connected (784 -> 32 -> 10,
  ReLU) MNIST-style digit classifier, exported as plain JSON:
  - `"w1"`: 784 x 32 matrix (list of 784 rows, each with 32 floats), input->hidden
  - `"b1"`: 32 bias floats (hidden)
  - `"w2"`: 32 x 10 matrix (list of 32 rows, each with 10 floats), hidden->output
  - `"b2"`: 10 bias floats (output)
- `reference.py` — a working reference implementation:
  `python3 reference.py <image>` prints the predicted digit.
- `data/img_0000.raw` … `data/img_0059.raw` — 60 raw grayscale images, each
  exactly 784 bytes (28x28 pixels, row-major, one byte per pixel, values
  0..255).

## What to build

A C program `/app/predict.c` that, when compiled with `gcc -O2 -o /app/predict
/app/predict.c`, reads a raw 784-byte image and prints the predicted digit
(`0`..`9`) plus a newline. Command line ABI is fixed:

```
/app/predict /path/to/image.raw
```

The program must reproduce the reference classifier **exactly**:

1. **inspect the shapes** in `model.json` before coding (784 inputs, 32 hidden
   ReLU units, 10 outputs).
2. Convert the JSON weights into a compact binary your C program can read
   (e.g. `/app/weights.bin`: 4 float32 arrays, row-major, little-endian).
   The format is your choice — the C source is what matters.
3. **Preprocessing must match exactly**: pixel value `v` becomes
   `v / 255.0f`.
4. Forward pass: `h = relu(x @ w1 + b1)`, then `y = h @ w2 + b2`, argmax over
   the 10 outputs. Floating point is `float` (32-bit).
5. The program must be **self-contained C**: it may only read the weights file
   and the image file, and may not launch other processes, read other files,
   or call into a shell or another interpreter.

## Byte budget

`/app/predict.c` must be **at most 2048 bytes** (exact byte count of the file,
`wc -c`). Keep the code compact — this is part of the task. Validate after
every compression step: recompile and re-run against all 60 images in
`/app/data`, comparing with `python3 reference.py <img>`.

## Check that will be run

- `/app/predict.c` exists and `wc -c /app/predict.c` <= 2048.
- The source compiles with `gcc -O2` and contains no `system(`/`popen`/`exec`
  /`fork`/`python`/`/bin/sh`.
- The compiled program is run on a held-out set of raw images (not the ones in
  `/app/data`); its predictions must match the reference implementation
  (computed from `model.json` on the same images) on essentially all of them.

Compile it, test it, and leave both `/app/predict.c` and the compiled
`/app/predict` in place.