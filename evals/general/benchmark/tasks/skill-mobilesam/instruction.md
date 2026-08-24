In `/app` there is a MobileSAM-style (promptable segmentation) model and a test input:

- `/app/input/image.npy` — a single 32x32 grayscale image, shape `(1, 1, 32, 32)`, dtype float32.
- `/app/input/prompt.txt` — a point prompt: two integers on one line, `px py` (a pixel coordinate within the foreground).
- `/app/model/mobilesam.npz` — a small trained checkpoint with keys:
  - `W_img` shape `(1026, 32)`
  - `b_img` shape `(32,)`
  - `W_mask` shape `(32, 1024)`
  - `b_mask` shape `(1024,)`

Write a Python script `/app/segment.py` that:

1. Loads the image, flattens it to a 1024-vector, and reads the point prompt `(px, py)`.
2. Builds the prompt-conditioned input vector `feat` = the concatenation of the flattened image and the two prompt values scaled `[px/32.0, py/32.0]` (so `feat` has length 1026).
3. Runs the decoder:
   - hidden = tanh(feat @ W_img + b_img)
   - mask_logits = hidden @ W_mask + b_mask, reshaped to `(32, 32)`
   - mask = sigmoid(mask_logits)  (elementwise `1/(1+exp(-z))`)
4. Saves the resulting `(32, 32)` mask as `/app/output/mask.npy` (dtype float32), and writes `/app/output/mask_count.txt` containing the number of mask pixels whose value is strictly greater than `0.5`.

`numpy` is already installed. Run the script so both output files exist with the correct contents.