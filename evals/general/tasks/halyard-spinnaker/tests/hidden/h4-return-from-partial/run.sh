#!/bin/bash
# Hidden case h4: returning partial called with a falsy string produced by
# ANOTHER returning partial (partial composition); the inner call itself is
# made with no argument and must also work.
set -u
HUGO_BIN=${HUGO_BIN:-/app/hugo}
work=$(mktemp -d /tmp/hc4.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/layouts/partials" "$work/content"
printf 'baseURL = "/"\n' > "$work/config.toml"
cat > "$work/layouts/index.html" <<'EOF'
MA{{ partial "retval" (partial "innerempty") }}MB
EOF
printf '{{ return "RV" }}\n' > "$work/layouts/partials/retval.html"
printf '{{ return "" }}\n' > "$work/layouts/partials/innerempty.html"
printf -- '---\n---\nhello\n' > "$work/content/_index.md"
( cd "$work" && "$HUGO_BIN" --source . --destination public --quiet >/dev/null 2>&1 )
rc=$?
[ $rc -eq 0 ] || exit $rc
cat "$work/public/index.html"