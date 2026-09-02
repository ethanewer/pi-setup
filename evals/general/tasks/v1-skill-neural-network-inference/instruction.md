In `/app/data` there is a small trained neural network and one test input:

- `x.npy` — a single feature vector, shape `(1, 6)`, float32.
- `net.npz` — saved network weights with keys:
  - `W1` shape `(6, 4)`
  - `b1` shape `(4,)`
  - `W2` shape `(4, 3)`
  - `b2` shape `(3,)`

The network is a 2-layer MLP with a `tanh` hidden activation and a 3-class output head.

Write a Python script `/app/classify.py` that:

1. Loads `x.npy` and the four weight arrays from `/app/data/net.npz`.
2. Runs forward inference:
   - hidden = tanh(x @ W1 + b1)
   - logits = hidden @ W2 + b2
   - predicted class = argmax over the 3 logits (index of the largest)
3. Writes `/app/class.txt` containing just the predicted class index as an integer (`0`, `1`, or `2`), with no extra text.

`numpy` is already installed. Run the script so `/app/class.txt` exists with the correct value.