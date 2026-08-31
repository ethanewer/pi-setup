# Provision the Meridian Basin Observatory causal workbench

The observatory's analysis platform ("Meridian Basin") runs its causal-inference
notebooks in R through Jupyter. A fresh worker image was stamped out with the
**R runtime present but the workbench never provisioned**: the R analysis
packages and the IRkernel are shipped only as **vendored Debian packages**
(there is no network in `/app`), no R Jupyter kernel is registered, and one
stale kernelspec from an older image is broken. Your job is to write the
provisioning program, **run it now** so the workbench is live, and leave behind
a machine-readable report.

## What is provided in the environment

* `/app/workbench.conf` — the provisioning spec (read it; the values are fixed):
  ```
  kernel_name=rcw
  display_name=R Causal Workbench
  packages=data.table,jsonlite,IRkernel
  report=/app/workbench_report.json
  ```
* `/app/vendor/` — the vendored `.deb` packages (IRkernel and the causal
  analysis packages `data.table`, `jsonlite`, plus their R dependencies). They
  are **not installed**. `apt`/`dpkg` may be used **only against these local
  artifacts**; there is no network.
* `/app/notebooks/visible_check.ipynb` — an R notebook that must execute under
  the registered kernel.

## Deliverables (both required)

1. **`/app/provision.sh`** — an executable `bash` script that provisions the
   workbench. It must be **idempotent** (safe to re-run; skips or repeats work
   harmlessly) and must exit `0` when run on an already-provisioned container.
   Running it must make all of the following true:

   * The vendored R packages are installed so that from `Rscript`:
     `library(data.table)`, `library(jsonlite)` and `library(IRkernel)` all
     succeed (install them from `/app/vendor` — offline; do not fetch anything).
   * A **user-level** Jupyter kernelspec named exactly `rcw` (the
     `kernel_name` from the conf) with display name exactly `R Causal
     Workbench` is registered, e.g.:
     ```
     Rscript --vanilla -e 'IRkernel::installspec(name="rcw", displayname="R Causal Workbench", user=TRUE)'
     ```
     Its `kernel.json` `argv[0]` must be an existing, **executable** binary.
   * `jupyter kernelspec list` must show `rcw`, and **every** kernelspec it
     lists must have a `kernel.json` whose `argv[0]` exists and is executable.
     The stale kernelspec `legacy-r` shipped in the image has a dead `argv[0]`;
     remove or repair it so the integrity condition holds.
   * `/app/workbench_report.json` is (re)written with exactly these keys:

     ```json
     {
       "kernel": "rcw",
       "r_binary": "<absolute path, same as the rcw kernelspec argv[0]>",
       "packages": ["<package names that load, must include data.table, jsonlite, IRkernel>"],
       "r_version": "<the exact string printed by: Rscript --vanilla -e 'cat(paste(R.version$major, R.version$minor, sep=\".\"))'>"
     }
     ```

2. **`/app/workbench_report.json`** — the report produced by running
   `bash /app/provision.sh` on the current container.

## Hidden probes the grader will run

The grader re-runs `/app/provision.sh` (twice, to confirm idempotency), then
independently checks the kernelspec state, the report contents, and **executes
R notebooks through the registered `rcw` kernel** with
`jupyter nbconvert --to notebook --execute` — including hidden notebooks you
have not seen that use `data.table` and `jsonlite` (group-by aggregation,
JSON round-trips, joins). If the kernel is not correctly registered, or the
packages do not load, those executions fail.

## Rules

- Work under `/app` and the standard system paths (R site-library,
  `/root/.local/share/jupyter`, `/usr/local/share/jupyter`). Fully offline:
  no package may be fetched from the network.
- Do not modify `/app/workbench.conf`, `/app/vendor/`, or
  `/app/notebooks/`.
- `/app/provision.sh` must not hard-code outputs; it derives the report from
  the live environment.

## What "done" looks like (self-check commands)

```
bash /app/provision.sh && bash /app/provision.sh   # both exit 0
Rscript --vanilla -e 'library(data.table); library(jsonlite); library(IRkernel); cat("R_OK\n")'
jupyter kernelspec list
cat /app/workbench_report.json
jupyter nbconvert --to notebook --execute \
  --ExecutePreprocessor.timeout=90 --ExecutePreprocessor.kernel_name=rcw \
  --output /tmp/visible_out.ipynb /app/notebooks/visible_check.ipynb \
  && grep -o RCW_VISIBLE_OK /tmp/visible_out.ipynb
```
