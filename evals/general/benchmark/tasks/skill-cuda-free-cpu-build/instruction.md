Under `/app/project` is a small C++ project. It has a build configuration file `build_config.h` that can enable CUDA (GPU) acceleration, and a `Makefile` that turns `main.cpp` into an executable named `run`.

The host has **no CUDA toolchain** (no CUDA headers or GPU compiler), so a CUDA-enabled build fails to compile. Produce a correct **CPU-only build** so the project builds and runs on this GPU-less machine.

Work in `/app/project`:
1. Ensure `build_config.h` does **not** enable CUDA (the `USE_CUDA` macro must not be defined).
2. Build with `make` to produce the `run` binary.
3. Run `run` and save its output to `/app/run.txt`.

The expected single line in `/app/run.txt` is:
```
BUILD_TARGET=cpu
```

The verifier rebuilds from pristine CPU-mode sources and confirms `/app/run.txt` matches, and that the `run` binary exists.