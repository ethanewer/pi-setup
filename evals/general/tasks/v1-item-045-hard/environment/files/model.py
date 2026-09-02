import numpy as np


class ReLUMLP:
    """A two-layer (1 input -> hidden ReLU units -> 1 output) neural network
    that defines a scalar piecewise-linear function. It is meant to be used
    ONLY through its black-box `predict` method."""

    def __init__(self, num_hidden=5, w1_scale=1.2, b_scale=1.7, w2_scale=1.0,
                 seed=None):
        rng = np.random.default_rng(seed)
        self.h = int(num_hidden)
        self.w1 = rng.normal(0.0, w1_scale, size=self.h)
        self.b1 = rng.normal(0.0, b_scale, size=self.h)
        self.w2 = rng.normal(0.0, w2_scale, size=self.h)
        self.b2 = float(rng.normal(0.0, 0.3))

    def predict(self, x):
        xa = np.atleast_1d(np.asarray(x, dtype=float))
        H = np.maximum(0.0, self.w1[None, :] * xa[:, None] + self.b1[None, :])
        y = np.sum(H * self.w2[None, :], axis=1) + self.b2
        return float(y[0]) if xa.size == 1 else y

    def breakpoints(self):
        return sorted(-float(b) / wi
                      for wi, b in zip(self.w1, self.b1) if abs(wi) > 1e-12)


def load_model():
    return ReLUMLP(num_hidden=12, seed=20260730)