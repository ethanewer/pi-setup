#!/bin/bash
#
# kelp-notch oracle. Does the real work: writes the deliverable provisioning
# script, then runs it against the visible spec to install the canonical
# postfix virtual map and produce /app/list_manifest.json. Never reads /tests.
set -euo pipefail

SCRIPT="/app/provision_lists.sh"
MANIFEST="/app/list_manifest.json"

cat > "$SCRIPT" <<'SH'
#!/usr/bin/env bash
#
# provision_lists.sh <spec_file> <manifest_file>
#
# Idempotently provisions the Thornway mailing lists through the canonical
# postfix virtual-alias file /etc/postfix/virtual, registers it in main.cf,
# builds the lookup database, and writes a JSON manifest.
set -euo pipefail

spec="$1"
manifest="$2"
CANON=/etc/postfix/virtual

[ -r "$spec" ] || { echo "provision_lists: cannot read spec '$spec'" >&2; exit 1; }

tmp=$(mktemp)
clean=$(mktemp)
trap 'rm -f "$tmp" "$clean"' EXIT

# Parse the spec: trim whitespace, drop comments/blank lines, emit
# "address<TAB>recipient" pairs; derive the shared list domain.
domain=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  # trim leading/trailing whitespace
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  addr="$(printf '%s' "$line" | cut -f1 | sed -e 's/[[:space:]]*$//')"
  rcpt="$(printf '%s' "$line" | cut -f2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "$addr" ] || [ -z "$rcpt" ]; then
    echo "provision_lists: malformed spec line: $line" >&2
    exit 1
  fi
  case "$addr" in
    *@*) d="${addr#*@}" ;;
    *)   echo "provision_lists: address without domain: $addr" >&2; exit 1 ;;
  esac
  if [ -z "$domain" ]; then
    domain="$d"
  elif [ "$d" != "$domain" ]; then
    echo "provision_lists: inconsistent list domain: $addr" >&2
    exit 1
  fi
  printf '%s\t%s\n' "$addr" "$rcpt" >> "$clean"
done < "$spec"

[ -n "$domain" ] || { echo "provision_lists: empty spec" >&2; exit 1; }

# 1. Rewrite the CANONICAL file from scratch (no stale entries survive).
: > "$CANON"
while IFS="$(printf '\t')" read -r addr rcpt; do
  [ -n "$addr" ] || continue
  printf '%s\t%s\n' "$addr" "$rcpt" >> "$CANON"
done < "$clean"

# 2. Make postfix honor the canonical map, then build the lookup database.
postconf -e "virtual_alias_maps = hash:$CANON"
postconf -e "virtual_alias_domains = $domain"
postmap "$CANON"

# 3. Manifest (sorted by address).
python3 - "$clean" "$domain" "$manifest" <<'PY'
import json
import sys

spec_tmp, domain, out = sys.argv[1], sys.argv[2], sys.argv[3]
entries = []
with open(spec_tmp, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        addr, _, rcpt = line.partition("\t")
        entries.append({"address": addr, "recipient": rcpt})
entries.sort(key=lambda e: e["address"])
doc = {
    "domain": domain,
    "canonical_config": "/etc/postfix/virtual",
    "lists": entries,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
PY

echo "provision_lists: $domain -> $CANON (manifest: $manifest)"
SH

chmod 0755 "$SCRIPT"

# Run the provisioning against the visible spec to produce the deliverables.
bash "$SCRIPT" /app/lists.spec "$MANIFEST" >/dev/null

# Sanity: canonical file present, database built, lookups resolve.
[ -f /etc/postfix/virtual ]     || { echo "oracle: canonical file missing" >&2; exit 1; }
[ -f /etc/postfix/virtual.db ]  || { echo "oracle: virtual.db missing" >&2; exit 1; }
[ "$(postmap -q announce@lists.thornway.internal hash:/etc/postfix/virtual 2>/dev/null)" = "steward" ] \
  || { echo "oracle: visible lookup failed" >&2; exit 1; }
python3 -c "import json;json.load(open('$MANIFEST'))" \
  || { echo "oracle: manifest invalid" >&2; exit 1; }

echo "kelp-notch oracle complete"
exit 0
