#!/bin/bash
# Hidden case h3: returning partial called with FALSE computed by a cond
# expression rather than a literal `false`.
set -u
HUGO_BIN=${HUGO_BIN:-/app/hugo}
work=$(mktemp -d /tmp/hc3.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/layouts/partials" "$work/content"
printf 'baseURL = "/"\n' > "$work/config.toml"
cat > "$work/layouts/index.html" <<'EOF'
MA{{ partial "retval" (cond true false true) }}MB
EOF
printf '{{ return "RV" }}\n' > "$work/layouts/partials/retval.html"
printf -- '---\n---\nhello\n' > "$work/content/_index.md"
( cd "$work" && "$HUGO_BIN" --source . --destination public --quiet >/dev/null 2>&1 )
rc=$?
[ $rc -eq 0 ] || exit $rc
cat "$work/public/index.html"