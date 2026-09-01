#!/bin/bash
# Real oracle for olive-quarry: write the three deliverable scripts (this IS
# the work, not canned state), then RUN the commissioning script so the live
# environment is fixed. Never reads /tests.
set -eu

cat > /app/register_kernel.sh <<'SH'
#!/bin/bash
# Register an R IRkernel user kernelspec.
#   register_kernel.sh NAME DISPLAY_NAME [HOME_DIR]
# With HOME_DIR the spec lands under $HOME_DIR/.local/share/jupyter/kernels/NAME
# and is detected by `HOME=$HOME_DIR jupyter kernelspec list`.
set -eu
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: register_kernel.sh NAME DISPLAY_NAME [HOME_DIR]" >&2
  exit 2
fi
NAME="$1"
DISPLAY="$2"
HOMEDIR="${3:-$HOME}"
mkdir -p "$HOMEDIR"
export HOME="$HOMEDIR"
export R_USER="$HOMEDIR"
Rscript --vanilla -e \
  'a <- commandArgs(TRUE); IRkernel::installspec(name = a[1], displayname = a[2], user = TRUE)' \
  "$NAME" "$DISPLAY" >/dev/null
echo "register_kernel: registered '$NAME' under $HOMEDIR"
SH

cat > /app/install_rpkg.sh <<'SH'
#!/bin/bash
# Install an R source-package tarball.
#   install_rpkg.sh TARBALL [LIB_DIR]
set -eu
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: install_rpkg.sh TARBALL [LIB_DIR]" >&2
  exit 2
fi
TARBALL="$1"
if [ ! -f "$TARBALL" ]; then
  echo "install_rpkg: no such tarball: $TARBALL" >&2
  exit 2
fi
if [ "$#" -eq 2 ]; then
  LIB="$2"
else
  LIB="$(Rscript --vanilla -e 'cat(.libPaths()[1])')"
fi
mkdir -p "$LIB"
R CMD INSTALL -l "$LIB" "$TARBALL" >/dev/null
echo "install_rpkg: installed $TARBALL into $LIB"
SH

cat > /app/setup.sh <<'SH'
#!/bin/bash
# One-shot Causal Workbench commissioning (idempotent):
#  * register the kernel described in /app/workbench/kernel.conf
#  * install every vendored R package tarball that is not yet installed
set -eu
CONF="/app/workbench/kernel.conf"
if [ ! -f "$CONF" ]; then
  echo "setup: missing $CONF" >&2
  exit 2
fi
NAME="$(sed -n 's/^name=[[:space:]]*//p' "$CONF" | head -n 1 | tr -d '[:space:]')"
DISPLAY="$(sed -n 's/^display=[[:space:]]*//p' "$CONF" | head -n 1 | sed 's/[[:space:]]*$//')"
if [ -z "$NAME" ] || [ -z "$DISPLAY" ]; then
  echo "setup: could not parse name/display from $CONF" >&2
  exit 2
fi

# 1) kernel registration (idempotent: installspect --replace semantics)
/app/register_kernel.sh "$NAME" "$DISPLAY"

# 2) vendored R packages (skip ones already installed)
for tarball in /app/vendored/*.tar.gz; do
  [ -e "$tarball" ] || continue
  pkg="$(basename "$tarball" .tar.gz)"
  pkg="${pkg%%_*}"
  if Rscript --vanilla -e "suppressMessages(library('$pkg'))" >/dev/null 2>&1; then
    echo "setup: $pkg already installed, skipping"
  else
    /app/install_rpkg.sh "$tarball"
  fi
done

echo "setup: workbench commissioned (kernel '$NAME')"
SH

chmod +x /app/setup.sh /app/register_kernel.sh /app/install_rpkg.sh

# Commission the live environment now.
bash /app/setup.sh
# Prove idempotency of the delivered script on the live box.
bash /app/setup.sh

echo "solve.sh done"
ls -l /app/setup.sh /app/register_kernel.sh /app/install_rpkg.sh
jupyter kernelspec list
