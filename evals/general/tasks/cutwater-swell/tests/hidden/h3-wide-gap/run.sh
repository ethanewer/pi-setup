#!/bin/bash
# Hidden case h3: alternation where the wildcard branch has a TWO-character
# gap (e..x), with case variants and mid-line occurrences, plus a single-gap
# decoy line that must NOT match. The pre-fix binary silently drops every
# wide-gap line; must exit 0 with exactly the expected lines after the fix.
set -u
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/hc3.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
unset RIPGREP_CONFIG_PATH 2>/dev/null || true
cat > "$work/f" <<'EOF'
e--x
E--X
xx e--x yy
ex
EX
e-x
zzz
EOF
out=$("$RG_BIN" '(?i:e..x|ex)' "$work/f" 2>&1)
rc=$?
printf '%s\n' "$out"
[ "$rc" -eq 0 ] || exit 1
for want in 'e--x' 'E--X' 'xx e--x yy' 'ex' 'EX'; do
    printf '%s\n' "$out" | grep -Fqx "$want" || { echo "missing matching line: $want" >&2; exit 1; }
done
[ "$(printf '%s\n' "$out" | grep -c .)" -eq 5 ] || { echo "unexpected extra or missing output lines" >&2; exit 1; }
exit 0