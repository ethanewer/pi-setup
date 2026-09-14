#!/bin/bash
# Hidden case h1: returning partial called with an EMPTY STRING that arrives
# from the page's front matter via .Params.arg (variable indirection; the
# upstream regression test only uses literal falsy arguments).
set -u
HUGO_BIN=${HUGO_BIN:-/app/hugo}
work=$(mktemp -d /tmp/hc1.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/layouts/partials" "$work/content"
printf 'baseURL = "/"\n' > "$work/config.toml"
cat > "$work/layouts/index.html" <<'EOF'
MA{{ partial "retval" .Params.arg }}MB
EOF
printf '{{ return "RV" }}\n' > "$work/layouts/partials/retval.html"
printf -- '---\narg: ""\n---\nhello\n' > "$work/content/_index.md"
( cd "$work" && "$HUGO_BIN" --source . --destination public --quiet >/dev/null 2>&1 )
rc=$?
[ $rc -eq 0 ] || exit $rc
cat "$work/public/index.html"