# brine-ridge — build the saltern trainer, CPU-only

The **saltern** deep-learning trainer source tree lives at `/app/saltern`
(CMake project with a shared `core/` library, a `cpu/` trainer, and a `gpu/`
CUDA path). It **ships with the GPU path enabled by default** (`USE_GPU=ON`),
and this host is CPU-only: there is no CUDA toolkit and no GPU device. A
default configure therefore dies inside `gpu/enable_gpu.cmake`
(`find_package(CUDAToolkit REQUIRED)`).

Your job: configure and build the framework with the **GPU/CUDA path
disabled**, producing the CPU training binary, then run one real training
job. Work only inside `/app`. Do not modify `/app/saltern/` sources or
`/app/data/train.csv` (the verifier re-checks them byte-for-byte).

## Deliverables (all required, exact paths)

1. `/app/saltern/build/saltern_cpu` — the CPU-only trainer, built by
   configuring **with the GPU path explicitly disabled**:
   ```
   cmake -S /app/saltern -B /app/saltern/build -DUSE_GPU=OFF
   cmake --build /app/saltern/build
   ```
   The target name must be exactly `saltern_cpu` (keep the shipped
   `add_executable(saltern_cpu ...)`). The binary must not link against any
   CUDA library (no `libcuda`, `libcudart`, `libnvrtc`, `libcublas`,
   `libcudnn`, ...).
2. `/app/model.json` — the model produced by actually running the trainer on
   the visible dataset:
   ```
   /app/saltern/build/saltern_cpu --data /app/data/train.csv \
       --epochs 200 --lr 0.5 --out /app/model.json > /app/train-log.txt
   ```
3. `/app/train-log.txt` — the stdout of that run (one `epoch=<t> loss=<...>`
   line per epoch, ending with `epoch=200`).

## Trainer contract (must keep working on any conforming dataset)

`saltern_cpu --data <csv> --epochs <N> --lr <F> --out <json>` trains the
logistic model `p = sigmoid(w1*x1 + w2*x2 + b)` with **deterministic,
fixed-seed-free** semantics on CSV datasets of rows `x1,x2,y` (blank lines
and `#` comments skipped):

* weights start at exactly `w1 = w2 = b = 0`;
* per epoch (t = 1..N): compute `p_i` at the current weights over **all**
  samples in file order; gradients `g1 = mean((p_i - y_i) * x1_i)`,
  `g2 = mean((p_i - y_i) * x2_i)`, `gb = mean(p_i - y_i)`; update
  `w -= lr * g` once;
* after each update, print `epoch=<t> loss=<%.6f>` where loss is the mean
  binary cross-entropy at the **new** weights, with `p` clamped to
  `[1e-12, 1-1e-12]` before the log;
* the JSON output has exactly the keys `epochs` (int), `lr` (float),
  `w1`, `w2`, `b`, `final_loss` (all floats, `%.6f` formatting).

Do not change the training math, the flag names, or the output format — the
grader re-runs your binary unchanged on fresh hidden datasets and compares
against an independent reference implementation of the contract above.

## What the grader verifies (summary)

* `/app/saltern/build/saltern_cpu` exists and links **no** CUDA library;
* a fresh configure/build with `-DUSE_GPU=OFF` in a clean copy of your
  `/app/saltern` tree succeeds and yields the `saltern_cpu` target;
* the delivered binary and a freshly rebuilt one both reproduce the expected
  final model (within numeric tolerance) on hidden CSV datasets for the
  documented epoch/lr settings;
* `/app/model.json` and `/app/train-log.txt` match a re-run of your binary on
  the visible dataset with `--epochs 200 --lr 0.5`.

There is no network access and no GPU at any point.
