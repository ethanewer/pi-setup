You are implementing **Gaussian Process (GP) regression** to predict a smooth function from noisy observations, using a squared-exponential (RBF) kernel.

In `/app`:
- `/app/xtrain.json`: training inputs (JSON array of floats): `[-2.0, -1.0, 0.0, 1.0, 2.0, 3.0]`
- `/app/ytrain.json`: training observations (JSON array): `[4.5, 0.5, 1.5, 0.5, 4.5, 22.0]`
- `/app/xtest.json`: test inputs: `[0.5, 1.5, 2.5]`

The RBF kernel is `k(a, b) = exp( -((a - b)^2) / (2 * l^2) )` with lengthscale `l = 1.5`. The observation noise variance is `sigma^2 = 0.1`.

The GP predictive mean at test point `t` (zero prior mean) is:
```
mean(t) = k(t, xtrain) · (K + sigma^2 I)^-1 · ytrain
```
where `K` is the (N x N) kernel matrix between training inputs, and `·` is the matrix product with the row vector `k(t, xtrain)`.

Use the `numpy` library. Write `/app/gp.py` that computes the predictive mean at each test point and writes `/app/gp_predictions.json` as a JSON array of floats, each rounded to 4 decimals:
```json
[0.1234, 0.5678, ...]
```

Run your script so `/app/gp_predictions.json` contains the correct values. `numpy` is already installed.