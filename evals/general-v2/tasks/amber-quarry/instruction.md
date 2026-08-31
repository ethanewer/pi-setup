# Quarry Calibration — mirror the ONNX calibration graph in pure numpy

The quarry ops team ships a small **calibration network** as an ONNX graph.
For embedded deployment you must provide a **pure-numpy mirror** of that
graph that reproduces the onnxruntime reference outputs within a tight
numeric tolerance — on fixed inputs and on random inputs. The mirror may
*parse* the graph, but must never *execute* it with onnxruntime (blocked at
verify time).

Everything runs on CPU in `/app` with `python3`, `numpy`, `onnx` and
`onnxruntime` (installed). Work only in `/app`; do not read `/tests` or
`/solution`.

## The graph (identical structure in every case, different shapes/weights)

Float32, opset 17, input `x` of shape `[B, D]`, output `out` of shape
`[B, K]`:

```
h1 = x  @ W1 + b1                       # D -> H
a1 = 0.5 * h1 * (1 + erf(h1 / sqrt(2))) # Gelu, erf form
n1 = LayerNormalization(a1, g1, beta1)  # axis=-1, epsilon=1e-5
h2 = n1 @ W2 + b2                       # H -> H
a2 = 0.5 * h2 * (1 + erf(h2 / sqrt(2))) # Gelu, erf form
o1 = a2 @ W3 + b3                       # H -> K
out = Softmax(o1, axis=-1)
```

The initializers are named exactly `W1, b1, g1, beta1, W2, b2, W3, b3`
(plus small constants). The Gelu subgraph is literally
`Div(h, sqrt(2)) -> Erf -> Add(1) -> Mul(h) -> Mul(0.5)`.

## Deliverables (both produced in `/app`)

1. `/app/mirror.py` — a standalone program:

   ```
   python3 /app/mirror.py <model.onnx> <inputs.npz> <output.npz>
   ```

   It loads `<model.onnx>` with the `onnx` package (graph parsing only),
   reads array `x` from `<inputs.npz>`, evaluates the graph in numpy, and
   writes the softmax output under key `out` into `<output.npz>`.
   Implementation rules:
   - **pure numpy + standard library** for the math (you may use
     `math.erf` via vectorization); do NOT import `onnxruntime`, `torch`,
     `tensorflow`, `jax` or `keras` — the verifier blocks `onnxruntime`
     imports and scans your source.
   - compute in double precision internally and cast the final result to
     float32, so the numeric error stays far inside the tolerance;
   - support exactly the ops above (`MatMul`, `Add`, `Mul`, `Div`, `Erf`,
     `LayerNormalization`, `Softmax`), reading `axis` / `epsilon`
     attributes from the graph rather than assuming defaults.

2. `/app/answer.npz` — the output of running your mirror on the visible
   case:

   ```
   python3 /app/mirror.py /app/case/model.onnx /app/case/inputs_fixed.npz /app/answer.npz
   ```

## How the grader checks parity

For the visible case `/app/case/` and for each hidden case, the grader:

1. runs `/app/mirror.py` on the case's **fixed** inputs
   (`inputs_fixed.npz`) and compares to an onnxruntime reference;
2. generates **random** inputs as
   `np.random.default_rng(meta["random_seed"]).standard_normal((meta["random_batch"], meta["in_dim"])).astype(np.float32)`,
   runs `/app/mirror.py`, and compares to the reference;
3. requires every comparison to satisfy
   `np.allclose(got, ref, atol=meta["atol"], rtol=meta["rtol"])`
   (default tolerance: `atol=1e-4`, `rtol=1e-3`), with finite values and
   the exact reference shape `[B, K]`;
4. for the visible case, additionally checks `/app/answer.npz` against the
   fixed-input reference.

Hidden cases differ in `D`, `H`, `K`, batch sizes, seeds and weights — your
mirror must read all shapes and weights from the graph, never hardcode.

## Constraints

- Standard library + `numpy` + `onnx` (parsing) only. No network at verify
  time.
- The verifier runs your program with `onnxruntime` imports blocked; if the
  program tries to import it, the run fails.
- Keep the numeric drift small: the tolerance is intentionally tight, and
  reordering the softmax (unstable `exp`) or computing Gelu in single
  precision can exceed it on adversarial magnitudes.
