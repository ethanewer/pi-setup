# Build a CUDA-free CPU trainer (Caffe-style) and complete a 500-iteration CIFAR-style run

## Context

`/app` contains a minimal, **Caffe-1.0-style, CPU-only ("CUDA-free")** linear
softmax trainer in C++. It reads a solver and a net configuration
(protobuf-like `.prototxt`), loads a CIFAR-style binary dataset, and trains,
emitting a per-iteration log.

This is the **hard** variant: the source is organized as a genuine multi-unit
**dependency build** (protobuf-style reader + BLAS helpers + a small
OpenCV-style image-preprocess unit), the dataset is large (2000 records), and
the solver demands an exact 500-iteration budget that the trainer must honor
even under resource pressure. You compile the dependencies, link the trainer,
run it for exactly the requested budget, and produce a short factual report.

## Files

- `/app/src/` — C++ sources (multiple translation units): `main.cpp` (the
  trainer), `tiny_proto.cpp` (protobuf-style config reader),
  `tiny_blas.cpp` (BLAS-like softmax helpers), `imgproc.cpp` (OpenCV-flavored
  image preprocessing), plus matching headers.
- `/app/Makefile` — **two-stage** build. Stage 1 compiles `tiny_proto.cpp`,
  `tiny_blas.cpp`, and `imgproc.cpp` into object files. Stage 2 links
  `main.cpp` against those compiled dependencies to produce the `train`
  binary. Run it with `make`.
- `/app/model/solver.prototxt` — solver config: `base_lr`, `max_iter`
  (**500**), `batch_size`, `seed`, `data_dir`, `log`, `net`. The exact
  iteration budget and the output log path live here.
- `/app/model/net.prototxt` — network config (`input_dim`, `num_classes`).
- `/app/data/train.bin` — CIFAR-style dataset, **2000 records** (each record =
  1 label byte + 3072 pixel bytes).

## Steps

1. **Build the dependency chain**: in `/app`, run `make`. This compiles the
   three dependency units (stage 1) then links `train` (stage 2). The binary
   lands at `/app/train`. If `make`/`g++` is missing, install the standard
   build tools.
2. **Run**: create `/app/run/` if needed and run
   `./train -solver /app/model/solver.prototxt`. The log path comes from the
   solver's `log` key (`/app/run/train.log`).
3. **Inspect the log**:
   - The first line is a `# ... CUDA-OFF CPU-BUILD CPU` header (the build is
     CPU-only).
   - Each success line is `Iteration <n>, loss = <v>`.
   - The trainer writes a `SOLVER_ENDED_MAX_ITER <n>` trailer when it stops at
     the configured limit.
   - Confirm the run stopped at **exactly** `max_iter` (500) — it must **honor**
     the exact budget, not overshoot.
4. **Report**: write `/app/run/report.json` containing exactly:

   ```json
   {
     "max_iter": 500,
     "iters": <iterations observed, int>,
     "first_loss": <first Iteration loss, rounded 6>,
     "last_loss": <last Iteration loss, rounded 6>,
     "cpu": true
   }
   ```

## Success criteria

- `/app/train` exists and the compiled dependencies (`tiny_proto.o`,
  `tiny_blas.o`, `imgproc.o`) are present in `/app` (the dependency build
  happened).
- `/app/run/train.log` contains **exactly 500** `Iteration ` lines numbered
  `1..500`, records the CPU build in the header, shows the loss **decreased**
  overall (last < first), and ends with `SOLVER_ENDED_MAX_ITER 500`.
- `/app/run/report.json` exists, matches the log, and reports `iters=500`,
  `max_iter=500`, `cpu=true`.
