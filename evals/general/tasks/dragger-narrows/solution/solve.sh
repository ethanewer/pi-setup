#!/bin/bash
# Oracle for dragger-narrows. Applies the real upstream fix to the pinned
# parent tree (as an uncommitted change to the version-file parser), writes
# the reproduction deliverable, rebuilds the uv binary and self-verifies that
# the reproduction now prints the pinned requests.
set -u

SRC=/app/src
export PATH=/opt/cargo/bin:$PATH

cd "$SRC" || { echo "no /app/src" >&2; exit 1; }

# Apply the fix (exactly the upstream change) as an uncommitted working-tree
# edit, in place of the buggy parser.
git apply --whitespace=nowarn /solution/fix.patch \
  || { echo "failed to apply the fix patch" >&2; exit 1; }

# The reproduction deliverable.
cp /solution/repro.sh /app/repro.sh
chmod +x /app/repro.sh

# Rebuild the project's real binary from the fixed tree.
cargo build -p uv > /tmp/oracle-build.log 2>&1 \
  || { echo "cargo build failed:" >&2; tail -30 /tmp/oracle-build.log >&2; exit 1; }

# Self-check: the reproduction must now print both pinned requests and emit
# no "unsupported request" warning.
OUT=$(UV_BIN="$SRC/target/debug/uv" bash /app/repro.sh </dev/null 2>/tmp/oracle-repro.err)
if printf '%s\n' "$OUT" | grep -qx "3.12" && printf '%s\n' "$OUT" | grep -qx "3.10" \
   && ! grep -q "Ignoring unsupported" /tmp/oracle-repro.err; then
  echo "oracle ok: reproduction prints 3.12 and 3.10 with no warnings"
else
  echo "oracle repro check failed; stdout=[$OUT]" >&2
  exit 1
fi
exit 0