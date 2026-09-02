import sys
import numpy as np


def gen(seed, n, d=24, scale=1.0, noise=0.03):
    rng = np.random.default_rng(seed)
    X = (rng.standard_normal((n, d)) * scale)
    y = (0.6 * np.maximum(X[:, 0], 0.0)
         + 0.5 * X[:, 1] * X[:, 2]
         + 0.4 * np.tanh(1.5 * X[:, 3])
         + 0.3 * X[:, 6]
         + 0.25 * np.maximum(-X[:, 4], 0.0)
         + noise * rng.standard_normal(n))
    return X.astype(np.float32), y.astype(np.float32)


if __name__ == "__main__":
    out = sys.argv[1]
    for name, seed, n, scale in [
        ("train", 20310101, 4096, 1.0),
        ("eval", 20310201, 1024, 1.0),
        ("eval_h1", 20310301, 1024, 1.0),
        ("eval_h2", 20310401, 1024, 1.05),
    ]:
        X, y = gen(seed, n, scale=scale)
        np.savez("%s/%s.npz" % (out, name), X=X, y=y)
        print(name, X.shape, "std(y)=%.4f" % float(y.std()))
