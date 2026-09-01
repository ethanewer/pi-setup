"""BlackBox fixture for mica-marsh (generated; deterministic).

The ONLY permitted channel is `query`; do not inspect private attributes
(they are not part of the contract).
"""
import numpy as np

_W = np.array([[-1.360355, 0.0, 0.0, -1.371062, 1.267781, 1.479264], [0.0, 0.745283, 1.298517, 0.0, -1.254587, 0.0], [-0.513129, 0.0, -0.98295, -0.712044, 0.467663, 0.488867], [0.0, -1.365507, -1.386944, 0.981339, 1.110521, -0.545993], [0.0, 0.0, -0.912316, -0.762292, -0.676196, -0.527484], [-1.283525, -1.231356, -0.456401, -0.863926, -0.433417, 1.171364], [1.199822, 0.0, 0.0, -1.388602, 0.616794, -0.40163], [-1.215305, 1.040195, 1.304378, -0.715753, 1.075327, 0.531756]], dtype=float)   # (n_units, in_dim)
_V = np.array([1.072859, -1.478315, -1.509886, 0.628551, -1.449874, -1.360429, -1.627171, 1.145406], dtype=float)
_B = np.array([-0.617652, -1.043172, -1.38746, -2.612705, -2.751071, 2.657102, 2.769551, 1.314318], dtype=float)


class BlackBox:
    in_dim = 6
    n_units = 8

    def query(self, x):
        """f(x) = sum_i v_i * relu(w_i . x + b_i); x is array-like of length in_dim."""
        x = np.asarray(x, dtype=float).reshape(-1)
        if x.shape[0] != self.in_dim:
            raise ValueError("input length %d != in_dim %d" % (x.shape[0], self.in_dim))
        return float(np.sum(_V * np.maximum(_W @ x + _B, 0.0)))
