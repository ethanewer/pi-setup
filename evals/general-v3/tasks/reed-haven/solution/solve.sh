#!/bin/bash
# Real oracle for reed-haven: author /app/provision.sh (idempotent provisioning
# that installs the canonical listd config and replays the visible stream),
# then RUN it to produce /app/roster.json. Never reads /tests.
set -eu

PROVISION="/app/provision.sh"
ROSTER="/app/roster.json"

# ---- 1. Write the deliverable provisioning script (this IS the work).
cat > "$PROVISION" <<'SH'
#!/bin/bash
# reed-haven provisioning: install the canonical listd config, then replay the
# visible administrative stream. Idempotent: every run rewrites the same
# config and regenerates the same report.
set -eu

LISTD=/app/listd.py
STREAM=/app/fixtures/stream.txt
CONFIG=/etc/listd/config.toml
OUT=/app/roster.json

mkdir -p /etc/listd

cat > "$CONFIG" <<'TOML'
# Reedhaven Naturalist Society -- canonical listd configuration.

[site]
domain = "reedhaven.example"
owner = "keeper@reedhaven.example"

# Closed announcement list: full normalized, de-duplicated roster from
# /app/fixtures/roster-source.txt, moderated by the keeper.
[[list]]
name = "heron-announce"
members = [
  "ada.l@example.net",
  "grace@hopper.example",
  "linm@pond.example",
  "tide-fan42@stream.example",
  "keeper@reedhaven.example",
]
moderators = ["keeper@reedhaven.example"]
open = false
max_members = 40

# Open discussion list: two seed members, hard cap of 3 members.
[[list]]
name = "tide-chat"
members = [
  "grace@hopper.example",
  "tide-fan42@stream.example",
]
moderators = ["keeper@reedhaven.example"]
open = true
max_members = 3
TOML

python3 "$LISTD" --config "$CONFIG" --stream "$STREAM" --out "$OUT"

echo "provision.sh: installed $CONFIG and wrote $OUT"
SH
chmod +x "$PROVISION"

# ---- 2. Run the provisioning deliverable to generate the visible roster.
bash "$PROVISION"

echo "solve.sh done -> $PROVISION and $ROSTER"
ls -l "$PROVISION" "$ROSTER" /etc/listd/config.toml
