#!/bin/bash
# Real oracle for kestrel-marsh: write the idempotent provisioning script, run
# it to provision the environment, then execute the visible probe notebook.
# Never reads /tests.
set -eu

SETUP="/app/setup_r_env.sh"
EXECUTED="/app/analysis/causal_probe.executed.ipynb"

# ---- 1. Write the provisioning script (this IS the work, not a canned state).
cat > "$SETUP" <<'SH'
#!/usr/bin/env bash
# Idempotent offline provisioner for the Causal Lab R notebook environment.
set -uo pipefail

REPO="/app/offline-repo"
KDIR="/root/.local/share/jupyter/kernels"
PROBE_SRC="/app/analysis/causal_probe.ipynb"
PROBE_OUT="/app/analysis/causal_probe.executed.ipynb"

r_have() { # r_have <pkg> -> 0 if installed and loadable
    Rscript --vanilla -e "cat(requireNamespace('$1', quietly=TRUE))" >/dev/null 2>&1 \
        && [ "$(Rscript --vanilla -e "cat(requireNamespace('$1', quietly=TRUE))" 2>/dev/null)" = "TRUE" ]
}

# 1) Install the R package closure (dependency order), skipping done work.
ORDER="base64enc digest evaluate fastmap glue rlang cli lifecycle utf8 vctrs crayon jsonlite uuid pbdZMQ htmltools pillar repr IRdisplay IRkernel"
for pkg in $ORDER; do
    if ! r_have "$pkg"; then
        tarball="$(ls "$REPO"/"${pkg}_"*.tar.gz 2>/dev/null | head -n 1)"
        if [ -z "$tarball" ]; then
            echo "setup_r_env: missing source tarball for $pkg in $REPO" >&2
            exit 1
        fi
        R CMD INSTALL --quiet --no-multiarch --with-keep.source "$tarball" >/dev/null
    fi
done

# 2) Remove the stale r_old kernelspec.
if [ -e "$KDIR/r_old" ]; then
    jupyter kernelspec remove -y r_old >/dev/null 2>&1 || true
    rm -rf "$KDIR/r_old"
fi

# 3) Register the user-level causalr kernelspec.
if [ ! -f "$KDIR/causalr/kernel.json" ]; then
    Rscript --vanilla -e 'IRkernel::installspec(name="causalr", displayname="Causal Lab R", user=TRUE)' >/dev/null
fi

# 4) Execute the visible probe notebook if not already done.
if [ ! -f "$PROBE_OUT" ]; then
    jupyter nbconvert --to notebook --execute \
        --ExecutePreprocessor.kernel_name=causalr \
        --ExecutePreprocessor.timeout=120 \
        --output causal_probe.executed.ipynb --output-dir /app/analysis \
        "$PROBE_SRC" >/dev/null 2>&1
fi

exit 0
SH
chmod +x "$SETUP"

# ---- 2. Run the provisioner to bring the live environment to the target state.
bash "$SETUP"

echo "solve.sh done -> $SETUP and $EXECUTED"
ls -l "$SETUP" "$EXECUTED"
