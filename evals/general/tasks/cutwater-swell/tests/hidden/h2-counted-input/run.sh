#!/bin/bash
# Hidden case h2: `rg -c` must count EVERY matching line for the defect
# pattern over a large input mixing several match variants (different case,
# mid-line, exact alternative), plus non-matching decoys. The pre-fix binary
# under-counts (only the exact-alternative lines are seen); must report the
# full count after the fix.
set -u
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/hc2.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
unset RIPGREP_CONFIG_PATH 2>/dev/null || true
{ yes 'e-x' | head -500; yes 'xx e-x yy' | head -23; yes 'ex' | head -17; yes 'E-X' | head -9; yes 'nomatch zzz' | head -40; } > "$work/f"
out=$("$RG_BIN" -c '(?i:e.x|ex)' "$work/f" 2>&1)
rc=$?
printf '%s\n' "$out"
[ "$rc" -eq 0 ] || exit 1
[ "$out" = "549" ] || { echo "expected count 549, got [$out]" >&2; exit 1; }
exit 0