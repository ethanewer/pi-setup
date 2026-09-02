"""BlackBox fixture for mica-marsh (generated; deterministic).

The ONLY permitted channel is `query`; do not inspect private attributes
(they are not part of the contract).
"""
import numpy as np

_W = np.array([[1.084631, 1.056411, 1.017216], [-1.313928, 0.610133, 0.0], [-0.753561, 1.198606, 0.742269], [0.0, 0.803028, 0.0], [1.437679, 1.051238, -1.068124]], dtype=float)   # (n_units, in_dim)
_V = np.array([-1.151782, 1.070382, 0.876111, 1.617489, -1.634388], dtype=float)
_B = np.array([2.074256, 2.957541, 0.048419, -0.451218, 0.106148], dtype=float)


class BlackBox:
    in_dim = 3
    n_units = 5

    def query(self, x):
        """f(x) = sum_i v_i * relu(w_i . x + b_i); x is array-like of length in_dim."""
        x = np.asarray(x, dtype=float).reshape(-1)
        if x.shape[0] != self.in_dim:
            raise ValueError("input length %d != in_dim %d" % (x.shape[0], self.in_dim))
        return float(np.sum(_V * np.maximum(_W @ x + _B, 0.0)))
