#!/bin/bash
# Hidden case h1: the same case-insensitive-alternation defect with a
# DIFFERENT alphabet than the documented example (t.t|tt instead of e.x|ex),
# on a mixed file where the pre-fix binary silently drops some matching lines
# while still exiting 0. Fails on the unfixed tree (the t-t and xx t-t yy
# lines vanish); must exit 0 with all matching lines present after the fix.
set -u
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/hc1.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
unset RIPGREP_CONFIG_PATH 2>/dev/null || true
cat > "$work/f" <<'EOF'
t-t
tt
tTT
plain
xx t-t yy
EOF
out=$("$RG_BIN" '(?i:t.t|tt)' "$work/f" 2>&1)
rc=$?
printf '%s\n' "$out"
[ "$rc" -eq 0 ] || exit 1
for want in 't-t' 'tt' 'tTT' 'xx t-t yy'; do
    printf '%s\n' "$out" | grep -Fqx "$want" || { echo "missing matching line: $want" >&2; exit 1; }
done
[ "$(printf '%s\n' "$out" | grep -c .)" -eq 4 ] || { echo "unexpected extra output lines" >&2; exit 1; }
exit 0