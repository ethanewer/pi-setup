#!/bin/bash
# Hidden case h2: returning partial called with an EMPTY LIST that arrives
# from a YAML data file (site.Data.misc.items); upstream test only uses
# literal `slice`.
set -u
HUGO_BIN=${HUGO_BIN:-/app/hugo}
work=$(mktemp -d /tmp/hc2.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/layouts/partials" "$work/content" "$work/data"
printf 'baseURL = "/"\n' > "$work/config.toml"
cat > "$work/layouts/index.html" <<'EOF'
MA{{ partial "retval" (site.Data.misc.items) }}MB
EOF
printf '{{ return "RV" }}\n' > "$work/layouts/partials/retval.html"
printf 'items: []\n' > "$work/data/misc.yaml"
printf -- '---\n---\nhello\n' > "$work/content/_index.md"
( cd "$work" && "$HUGO_BIN" --source . --destination public --quiet >/dev/null 2>&1 )
rc=$?
[ $rc -eq 0 ] || exit $rc
cat "$work/public/index.html"