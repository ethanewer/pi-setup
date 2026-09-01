#!/usr/bin/env bash
# Oracle for wren-link: write the generic link.sh, coalesce the shipped modules,
# and build the native demo. Never reads /tests.
set -euo pipefail

cat > /app/link.sh <<'EOF'
#!/usr/bin/env bash
# Generic LLVM IR coalescer: link.sh OUT.bc IN1.ll [IN2.ll ...]
set -euo pipefail
if [ "$#" -lt 2 ]; then
  echo "usage: link.sh OUT.bc IN1.ll [IN2.ll ...]" >&2
  exit 2
fi
out=$1; shift
for f in "$@"; do
  [ -f "$f" ] || { echo "link.sh: input not found: $f" >&2; exit 2; }
done
linker=""
for cand in llvm-link-18 llvm-link-17 llvm-link-16 llvm-link-15 llvm-link-14 llvm-link; do
  if command -v "$cand" >/dev/null 2>&1; then linker="$cand"; break; fi
done
[ -n "$linker" ] || { echo "link.sh: no llvm-link found" >&2; exit 3; }
"$linker" -o "$out" "$@"
EOF
chmod +x /app/link.sh

/app/link.sh /app/plugin.bc /app/src/gain.ll /app/src/envelope.ll /app/src/limiter.ll

clang-18 -c -emit-llvm /app/src/main.c -o /tmp/main.bc
clang-18 -O1 /tmp/main.bc /app/plugin.bc -o /app/skerry_demo
chmod +x /app/skerry_demo

# sanity: run it
/app/skerry_demo

echo "solve.sh done"
