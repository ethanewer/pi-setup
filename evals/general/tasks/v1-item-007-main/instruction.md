# Build a CUDA-free CPU trainer and run a small CIFAR-style training run

## Context

`/app` contains a minimal, **Caffe-1.0-style, CPU-only ("CUDA-free")** trainer
in C++. It reads a solver and a net configuration (protobuf-like `.prototxt`),
loads a small CIFAR-style binary dataset, and trains a linear softmax
classifier, writing a per-iteration log.

Your job is to **build** the trainer, **run** it for the exact number of
iterations the solver requests, and **inspect its training log** to produce a
short factual report. Everything you need (source, Makefile, configs, data) is
already in the image — you only have to compile, run, and report.

## Files

- `/app/src/` — C++ sources (several translation units): `main.cpp`,
  `tiny_proto.cpp` (protobuf-style config reader), `tiny_blas.cpp` (BLAS-like
  helpers). Headers are in the same directory.
- `/app/Makefile` — builds the binary `train` from those units.
- `/app/model/solver.prototxt` — solver config. It contains (among others)
  `base_lr`, `max_iter`, `batch_size`, `seed`, `net`, `data_dir`, `log`. Read
  it to learn the exact iteration budget (`max_iter`) and the output log path.
- `/app/model/net.prototxt` — network config (`input_dim`, `num_classes`).
- `/app/data/train.bin` — the CIFAR-style dataset (200 records; each record is
  1 label byte + 3072 pixel bytes).

## Steps

1. **Build**: in `/app`, run `make` (uses `g++ -std=c++17 -O2`). This produces
   `/app/train`. (If `make`/`g++` is missing, install the standard build tools.)
   Treat this as building a small but real multi-unit C++ toolchain — link all
   three `.cpp` files.
2. **Run**: create `/app/run/` if needed and run
   `./train -solver /app/model/solver.prototxt`  (the `net:` and `log:` fields
   come from the solver config). The trainer writes the per-iteration log to
   the path in the solver's `log` key (`/app/run/train.log`).
3. **Inspect the log**: the log's first line is a header naming the CPU
   build. Each success line looks like `Iteration <n>, loss = <v>`. Confirm:
   - the run stopped at **exactly** `max_iter` iterations (the solver's exact
     value; the trainer must **honor it** and not overshoot),
   - the loss values decreased over the run (final `<` first).
   The trainer writes a `SOLVER_ENDED_MAX_ITER <n>` trailer when it stops at
   the configured limit.
4. **Report**: write `/app/run/report.json` containing **exactly**:

   ```json
   {
     "max_iter": <the solver's max_iter, as int>,
     "iters": <number of iteration lines observed, as int>,
     "first_loss": <the first Iteration loss, rounded to 6 decimals>,
     "last_loss": <the last Iteration loss, rounded to 6 decimals>,
     "monotonic": <true/false>,
     "cpu": <true>
   }
   ```

   `monotonic` is `true` if losses were non-increasing across the whole run,
   `cpu` is `true` because this is the CUDA-free CPU build.

## Success criteria

- `/app/train` exists (built successfully).
- `/app/run/train.log` contains exactly `max_iter` `Iteration ` lines, the
  header records the CPU build, loss decreased over the run, and the log ends
  with `SOLVER_ENDED_MAX_ITER <max_iter>`.
- `/app/run/report.json` exists with the schema above and matches the log.