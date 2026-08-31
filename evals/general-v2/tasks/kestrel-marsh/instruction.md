# Provision the Causal Lab offline R notebook environment

The Causal Lab analysis workstation is **air-gapped**: there is no network
access. It currently has R, a Jupyter/Python toolchain, and a local mirror of
R source packages under `/app/offline-repo/` — but no usable R kernel. You
must build the complete R notebook environment **from the local mirror only**
and prove it works by executing a notebook.

## Environment

- Working directory: `/app`.
- `R` / `Rscript` (R 4.x) are installed, along with compilers, `libzmq` headers
  and a Jupyter toolchain (`jupyter`, `jupyter nbconvert`, `nbclient`).
- `/app/offline-repo/` contains the **only** R package sources available — a
  mirror of `IRkernel` and every R package it transitively needs, plus the
  data-interchange package `jsonlite`. **No CRAN, apt, or pip access is
  possible**; anything you need must come from this directory.
- `/app/analysis/causal_probe.ipynb` is an unexecuted R notebook (its metadata
  already names the kernel you must create) and `/app/analysis/dag.json` is its
  input data.
- A stale, corrupted kernelspec `r_old` (whose `argv` points at a nonexistent R
  binary) is left over from a decommissioned image and must be gone from the
  environment when you finish.
- **Do not modify** `/app/analysis/causal_probe.ipynb` or
  `/app/analysis/dag.json`.

## Deliverables (both required)

1. **`/app/setup_r_env.sh`** — a `bash` provisioning script that brings the
   environment to the target state. It must be **idempotent** (safe to re-run;
   each step guarded so completed work is skipped quickly) and must exit `0`
   both when run on a freshly broken machine and when re-run on an already
   provisioned one. Running it must reach all of the target state below:

   - The R package closure required by `IRkernel` (and `jsonlite`) is installed
     into the system R library so that, from any directory,
     `requireNamespace("IRkernel")` and `requireNamespace("jsonlite")` are both
     TRUE.
   - An R Jupyter kernel is registered with the **exact name** `causalr` and
     display name **`Causal Lab R`**, as a **user-level** kernelspec at
     `/root/.local/share/jupyter/kernels/causalr/kernel.json` whose `argv[0]`
     is an existing, executable R binary. `jupyter kernelspec list` must list
     `causalr`.
   - The stale kernelspec `r_old` no longer exists (its directory is removed
     and it is not listed by `jupyter kernelspec list`).

   Your script must be **general**: the grader may re-run it on machines in
   intermediate states (some packages already installed, kernel present or
   absent, stale spec present or absent).

2. **`/app/analysis/causal_probe.executed.ipynb`** — the executed notebook
   produced by running
   ```
   jupyter nbconvert --to notebook --execute \
     --ExecutePreprocessor.kernel_name=causalr \
     --ExecutePreprocessor.timeout=120 \
     --output causal_probe.executed.ipynb --output-dir /app/analysis \
     /app/analysis/causal_probe.ipynb
   ```
   Every code cell must show a non-null execution count and the cell outputs
   produced by the `causalr` R kernel.

## What the grader checks

After you finish, the grader re-runs `/app/setup_r_env.sh`, then independently
verifies the kernel and packages: the `causalr` kernelspec (name, display name,
executable `argv`), that `r_old` is gone, that `library(jsonlite)` works in R,
that the executed notebook deliverable is valid, and that executing the visible
probe notebook via the `causalr` kernel produces its expected markers.

It then executes **hidden R probe notebooks** you have not seen (more
`jsonlite`-based DAG parsing/round-trip and kernel arithmetic probes) through
the registered `causalr` kernel and checks their outputs. Your environment must
therefore be complete and correct, not grafted to the visible probe: any R
notebook that uses `jsonlite` and base R arithmetic must execute successfully
under `causalr`.

## Rules

- Everything offline; use only `/app/offline-repo/` for R packages.
- Do not modify the two `/app/analysis/*` input files.
- Leave the environment fully provisioned (state the grader re-checks must be
  live, not just scripted).
