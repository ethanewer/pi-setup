"""BlackBox fixture for mica-marsh (generated; deterministic).

The ONLY permitted channel is `query`; do not inspect private attributes
(they are not part of the contract).
"""
import numpy as np

_W = np.array([[0.555211, 0.0, -0.78612, 1.232443], [0.899223, -1.399023, -0.467327, 1.277993], [0.77206, 0.991159, -0.997448, -0.803465], [1.188643, 1.453254, 1.44658, -0.753315], [1.449388, 0.415761, 0.0, 1.379741], [-0.626039, -0.620982, 1.293727, 0.0]], dtype=float)   # (n_units, in_dim)
_V = np.array([0.542376, 1.100017, 1.058603, -1.0782, 0.66548, 0.642922], dtype=float)
_B = np.array([-2.846268, 1.218183, -2.42733, 2.55582, -2.493539, 0.342061], dtype=float)


class BlackBox:
    in_dim = 4
    n_units = 6

    def query(self, x):
        """f(x) = sum_i v_i * relu(w_i . x + b_i); x is array-like of length in_dim."""
        x = np.asarray(x, dtype=float).reshape(-1)
        if x.shape[0] != self.in_dim:
            raise ValueError("input length %d != in_dim %d" % (x.shape[0], self.in_dim))
        return float(np.sum(_V * np.maximum(_W @ x + _B, 0.0)))
