In `/app/data` there is an MNIST-style digit classification task:

- `x.npy` — a single grayscale digit image, shape `(1, 784)`, float32. Each row is the 784 brightness values of a 28x28 digit, flattened row-major.
- `model.npz` — a saved neural network with keys:
  - `W1` shape `(784, 64)`
  - `b1` shape `(64,)`
  - `W2` shape `(64, 10)`
  - `b2` shape `(10,)`

Write a Python script `/app/predict.py` that:

1. Loads `x.npy` and the four arrays from `/app/data/model.npz`.
2. Runs forward inference for the single image:
   - hidden = sigmoid(x @ W1 + b1)
   - logits = hidden @ W2 + b2
   - predicted digit = argmax over the 10 logits (index of the largest logit)
3. Writes `/app/prediction.txt` containing just the predicted digit as an integer (0–9), with no extra text.

`numpy` is already installed. Run the script so `/app/prediction.txt` exists with the correct digit.