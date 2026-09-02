`/app/nn.py` provides a black-box binary classifier via a function `predict(x, y)` that returns `1` or `0` for a 2D feature point. It behaves like a small trained neural/perceptron model: it computes a weighted linear decision based on internal weights whose values you cannot read, only probe.

Your job is to use the black box empirically:
1. Import `/app/nn.py` and call `predict(x, y)` yourself on any points you like to learn which side of its (unknown) decision boundary is `1` and which is `0`.
2. Read the 10 test points from `/app/test_points.txt` (each line is two integers `x y`).
3. For each point, use your understanding to decide the prediction, and write the predicted label for every point (one `0` or `1` per line) to `/app/classifications.txt`.

The verifier queries `/app/nn.py` on the same points and requires your labels to match for all of them.
