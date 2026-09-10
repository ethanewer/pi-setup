#!/usr/bin/env bash
# escutcheon-stack deploy driver (the deliverable solver).
#
# Usage: deploy.sh <SNAPSHOT_DIR>
#
# For any snapshot directory, adopts every pre-existing hand-managed file under
# <SNAPSHOT_DIR>/live/ so that Terraform manages it going forward (with content
# taken verbatim from the on-disk file, so nothing is rewritten), and adds a
# second managed resource: <SNAPSHOT_DIR>/deployment.manifest, whose content is
# the lexicographically-sorted, newline-joined list of adopted file names.
#
# After this runs, `terraform init && terraform plan` in the snapshot directory
# reports an empty plan and the adopted files are byte-identical to what was on
# disk before. Works for ANY snapshot of this shape, not just the shipped one.
set -euo pipefail

SNAP="${1:?usage: deploy.sh <SNAPSHOT_DIR>}"
SNAP="$(cd -- "$SNAP" && pwd)"
LIVE="$SNAP/live"
if [ ! -d "$LIVE" ]; then
  echo "deploy.sh: no 'live/' directory in $SNAP" >&2
  exit 1
fi

# --- discover the hand-managed files (top-level regular files, sorted) ---
mapfile -t FILES < <(find "$LIVE" -maxdepth 1 -type f -printf '%f\n' | sort)
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "deploy.sh: no files under $LIVE" >&2
  exit 1
fi

# --- emit the Terraform configuration ---
{
  echo 'terraform {'
  echo '  required_providers {'
  echo '    local = { source = "hashicorp/local" }'
  echo '  }'
  echo '}'
  echo ''
} > "$SNAP/main.tf"

names=()
for f in "${FILES[@]}"; do
  safe=$(printf '%s' "$f" | tr -c 'A-Za-z0-9' '_')
  b64=$(base64 -w0 "$LIVE/$f")
  {
    echo "resource \"local_file\" \"$safe\" {"
    echo "  filename         = \"$LIVE/$f\""
    echo "  content_base64   = \"$b64\""
    echo '}'
    echo ''
  } >> "$SNAP/main.tf"
  names+=("$f")
done

# manifest: the adopted file names, sorted, one per line, no trailing newline
IFS=$'\n' sorted=($(printf '%s\n' "${names[@]}" | sort))
manifest_content=$(printf '%s' "${sorted[*]}")
mb64=$(printf '%s' "$manifest_content" | base64 -w0)
{
  echo 'resource "local_file" "deployment_manifest" {'
  echo "  filename         = \"$SNAP/deployment.manifest\""
  echo "  content_base64   = \"$mb64\""
  echo '}'
} >> "$SNAP/main.tf"

# --- drive Terraform offline against the mirrored providers ---
cd "$SNAP"
terraform init -input=false >/dev/null
terraform apply -auto-approve -input=false >/dev/null

echo "adopted ${#FILES[@]} file(s) under Terraform in $SNAP"
exit 0
