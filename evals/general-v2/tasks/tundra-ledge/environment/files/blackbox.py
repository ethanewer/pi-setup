import numpy as np

# tundra-ledge black-box fixture.
#
# The deliverable must recover a scalar one-hidden-layer ReLU network's input
# weight rows by interrogating the model ONLY through query(). The secret
# parameters below live in module scope and are never placed on any on-disk
# path nor printed; query() is the only permitted channel.

_HIDDEN = 6      # number of hidden ReLU units
_IN_DIM = 6      # input dimensionality
_SEED = 20240630


def make_params(seed: int = _SEED):
    """Deterministically produce the hidden (W, b, v) triple for this fixture."""
    rng = np.random.default_rng(seed)
    W = rng.normal(0.0, 1.2, size=(_HIDDEN, _IN_DIM))
    # push entries up out of a near-zero band so every unit provokes a kink on
    # every coordinate axis within the probe interval
    W = np.where(np.abs(W) < 0.8, np.sign(W) * (0.8 + 0.5 * np.abs(W)), W)
    b = rng.uniform(-2.0, 2.0, size=(_HIDDEN,))
    v = 1.0 + rng.uniform(0.0, 1.4, size=(_HIDDEN,))
    return W, b, v


_W, _b, _v = make_params(_SEED)


class BlackBox:
    """Scalar network  f(x) = sum_i v_i * ReLU(W_i . x + b_i)."""

    def __init__(self):
        self._in = _IN_DIM
        self._h = _HIDDEN
        self._W = _W
        self._b = _b
        self._v = _v

    @property
    def in_dim(self) -> int:
        return self._in

    @property
    def hidden(self) -> int:
        return self._h

    def query(self, x) -> float:
        """Return f(x).  x must be array-like of length in_dim."""
        x = np.asarray(x, dtype=np.float64).reshape(-1)
        if x.size != self._in:
            raise ValueError("expected input length %d" % self._in)
        return float(np.sum(self._v * np.maximum(self._W @ x + self._b, 0.0)))