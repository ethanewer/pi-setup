# Commission the Causal Workbench R runtime

`/app` is the working tree of an offline analytics box ("Causal Workbench")
that runs causal-inference notebooks. The container has R, the `IRkernel` R
package, and the `jupyter` CLI already installed — but the R Jupyter kernel
has **never been registered**, and the platform's two causal analysis R
packages are sitting **uninstalled** as vendored source tarballs. Commission
the runtime and leave behind the three deliverables below.

Everything you need is already on the box; there is no network at run time,
so installs must come from the local vendored artifacts only.

## What is on the box

* `/app/workbench/kernel.conf` — plain text, one `key=value` pair per line:
  ```
  name=<kernel-name>
  display=<display name>
  ```
* `/app/vendored/*.tar.gz` — R source packages (`R CMD INSTALL`-able):
  `graphloom` (graph/DAG helpers) and `frameforge` (data-frame helpers).
* R, `IRkernel`, `Rscript`, and `jupyter` are on `PATH`.

## Deliverables (create all three; all are graded)

### 1. `/app/setup.sh` — the one-shot commissioning script

Executable bash, no arguments, **idempotent** (running it again on an
already-commissioned box exits 0 and changes nothing harmful). It must:

* read `/app/workbench/kernel.conf` (do **not** hard-code the values — parse
  the file) and register an R Jupyter kernelspec with exactly that kernel
  `name` and `display` name, as a **user** kernelspec (lands under
  `/root/.local/share/jupyter/kernels/<name>/`);
* install every `R CMD INSTALL`-able package tarball found in
  `/app/vendored/*.tar.gz` into the default R library (first entry of
  `.libPaths()`), skipping any package that is already installed;
* exit 0 on success, and also exit 0 when re-run after everything is done.

After running it (you **must** actually run it — commissioning means the
live state is fixed, not just the script), `jupyter kernelspec list` must
detect the configured kernel by name, its `kernel.json` must exist with an
`argv[0]` that is an existing, executable R binary, and
`Rscript -e 'library(graphloom); library(frameforge)'` must work.

### 2. `/app/register_kernel.sh` — reusable kernel registrar

Executable bash with this interface:

```
/app/register_kernel.sh NAME DISPLAY_NAME [HOME_DIR]
```

Registers an **R IRkernel** user kernelspec named `NAME` with display name
`DISPLAY_NAME`. With the optional third argument `HOME_DIR`, the kernelspec
must be registered under that directory instead of the real home — i.e. the
resulting `kernel.json` must exist at
`$HOME_DIR/.local/share/jupyter/kernels/NAME/kernel.json` **and** the command

```
HOME=$HOME_DIR jupyter kernelspec list
```

must detect the kernel by that name (this is how the grader probes unseen
kernel names — the name detection must come from a real IRkernel
registration, not a hand-faked spec that jupyter cannot list). Without the
third argument it registers under the real user home. Re-running with the
same arguments must succeed (exit 0). `argv[0]` of the written `kernel.json`
must be an existing, executable R binary.

### 3. `/app/install_rpkg.sh` — reusable R package installer

Executable bash with this interface:

```
/app/install_rpkg.sh TARBALL [LIB_DIR]
```

Installs the given R source-package tarball with `R CMD INSTALL` into
`LIB_DIR` (creating it if needed); when `LIB_DIR` is omitted, install into
the first entry of `.libPaths()`. After it returns 0,
`Rscript -e 'library(<pkg>)'` with `R_LIBS=$LIB_DIR` must load the package.
Re-installing the same tarball must succeed (exit 0).

## Hidden probes the grader will run

* Re-runs `/app/setup.sh` **twice** and requires exit 0 both times, then
  checks the configured kernel is listed by `jupyter kernelspec list --json`
  with the configured display name and an executable R `argv[0]`, and that
  `library(IRkernel)`, `library(graphloom)`, `library(frameforge)` all work
  with the function results intact.
* Registers **unseen** kernel names/display strings through
  `/app/register_kernel.sh NAME DISPLAY TMPHOME` and verifies
  `HOME=TMPHOME jupyter kernelspec list --json` detects each name and that
  each written `kernel.json` has an executable R `argv[0]` and the right
  display name.
* Installs **unseen** R source-package tarballs through
  `/app/install_rpkg.sh TARBALL TMPLIB` and checks `library()` plus concrete
  function results of those packages with `R_LIBS=TMPLIB`.

So all three scripts must be **general** — parameterized, not hard-coded to
the visible kernel name, display name, or the two vendored packages.

## Rules

* Work under `/app` and the user jupyter/library paths only. Do not modify
  `/app/workbench/kernel.conf` or the vendored tarballs.
* No network at run time: installs must use the local artifacts and the
  already-installed `IRkernel`/`jupyter` stack. Do not attempt `install.packages()`
  from CRAN or `apt`/`pip` downloads.
* Use `IRkernel::installspec` (directly or via your registrar script) for
  kernel registration; the kernelspec must be a genuine R kernel spec that
  `jupyter kernelspec list` detects.

## Self-check commands

```
bash /app/setup.sh && bash /app/setup.sh          # idempotent, both exit 0
jupyter kernelspec list                            # detects the configured kernel
Rscript -e 'library(graphloom); print(gl_topo_order(c("A","B","C"), c("A>B","B>C")))'
Rscript -e 'library(frameforge); print(ff_dims(data.frame(x=1:3)))'
```
