# Bootstrap the air-gapped R runtime for the Osprey Ridge flow lab

The **Osprey Ridge** river-monitoring station runs an air-gapped (no network)
analysis workstation. A flow-statistics pipeline that shells out to the R
statistical runtime has been shipped to the box, but **R was never installed**,
so every R subprocess step fails. A complete offline `.deb` bundle for R is
vendored on the machine. Your job is to bring the R runtime up and prove the
pipeline runs end to end.

There is **no network** on this machine: install software only from the local
deb bundle. (`dpkg -i /app/debs/*.deb` installs the whole bundle in one
shot; every dependency R needs is inside it.)

## What is already on the box

- `/app/debs/` — the offline `.deb` bundle containing `r-base-core` and every
  package it needs (and nothing else).
- `/app/pipeline/riverlaunch.py` — the pipeline launcher. It reads
  `/app/pipeline/settings.json`, takes the R interpreter path from the
  `"rscript"` field, and runs the R stage:
  ```
  python3 /app/pipeline/riverlaunch.py <params-file> <output-file>
  ```
  On success it prints `RIVERLAUNCH_OK` and exits 0.
- `/app/pipeline/sampler.R` — the R stage. It reads a plain-text params file
  of `key=value` lines (`seed`, `n`, `mu`, `sigma`), draws `n` standard normal
  deviates with `set.seed(seed)` (R defaults), shifts/scales them to
  `x = mu + sigma * rnorm(n)`, and writes five `key=value` lines to the output
  file: `mean=`, `sd=`, `median=`, `min=`, `max=`, each formatted with six
  decimals.
- `/app/pipeline/settings.json` — currently has `"rscript": ""` (empty), which
  makes the launcher fail.
- `/app/pipeline/params_visible.txt` — the visible parameter set.

**Do not modify** `/app/pipeline/riverlaunch.py`, `/app/pipeline/sampler.R`,
or `/app/pipeline/params_visible.txt`. Do not add files under `/app/debs/`
or `/app/pipeline/` other than the deliverables listed below.

## Deliverables (all three required)

1. **`/app/setup_r.sh`** — a bash script that installs R **offline** from the
   local deb bundle. It must be **idempotent**: re-running it on a machine
   where R already works must change nothing and exit `0` quickly. If the
   bundle is missing it must print an error to stderr and exit nonzero. After
   it succeeds, `Rscript` must be resolvable **by bare name on the shell
   PATH** (i.e. `command -v Rscript` works in a fresh non-login shell) and
   `Rscript --vanilla -e 'cat("R_OK")'` must print `R_OK`.
2. **`/app/pipeline/settings.json`** — keep it valid JSON and set the
   `"rscript"` field to the **resolved absolute path** of an existing,
   executable `Rscript` binary. Keep any other fields unchanged.
3. **`/app/pipeline/selftest.txt`** — the output file produced by actually
   running the pipeline end to end on the visible params:
   ```
   python3 /app/pipeline/riverlaunch.py /app/pipeline/params_visible.txt /app/pipeline/selftest.txt
   ```
   The file must contain exactly the five `key=value` lines the R stage
   writes.

You must also **apply the work live**: after you finish, the environment
itself must be in the repaired state (R installed, settings wired, selftest
present) — the grader re-checks the live machine, re-runs
`bash /app/setup_r.sh` to confirm idempotency, and re-executes the pipeline
launcher.

## How the grader probes it

- The grader runs `bash /app/setup_r.sh` on the already-repaired box and
  requires exit 0 (idempotent).
- The grader requires bare-name `Rscript` PATH resolution **and** the
  `rscript` field in `settings.json` to be a working executable.
- The grader re-runs `python3 /app/pipeline/riverlaunch.py` on the visible
  params **and on hidden parameter sets** you have not seen (different seeds,
  sample counts — always `n >= 2` — means, including negative, and sigmas).
  For each set it independently recomputes the five statistics with its own R
  invocation of the exact spec above and compares all five values.
- `/app/pipeline/selftest.txt` must equal the visible-case output.

All inputs conform to the format above; there is no network anywhere in this
task. Do not attempt to fetch anything.
