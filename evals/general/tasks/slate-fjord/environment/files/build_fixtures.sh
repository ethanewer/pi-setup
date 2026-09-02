#!/bin/bash
# build_fixtures.sh - creates the bare repositories served by the loopback SSH
# git server for the "slate-fjord" mirror-sync task. Runs at image build time.
#
#   /srv/git/ledger.git   visible remote (default branch main, has history,
#                         no manifest.txt)
#   /srv/git/empty.git    hidden remote (completely empty, default branch main)
#   /srv/git/legacy.git   hidden remote (default branch master, already has a
#                         stale manifest.txt and a README to preserve)
#   /srv/git/quartz.git   hidden remote (default branch main; reached via the
#                         port-2222 endpoint)
set -euo pipefail

export GIT_AUTHOR_NAME="Tarrow Ops"
export GIT_AUTHOR_EMAIL="ops@tarrow.example"
export GIT_COMMITTER_NAME="Tarrow Ops"
export GIT_COMMITTER_EMAIL="ops@tarrow.example"
export GIT_CONFIG_NOSYSTEM=1

SRV=/srv/git
mkdir -p "$SRV"

seed_repo() {  # seed_repo <bare-path> <default-branch>
  git init -q --bare -b "$2" "$1"
}

# ------------------------------------------------------------- ledger.git (visible)
seed_repo "$SRV/ledger.git" main
SEED=$(mktemp -d)
git init -q -b main "$SEED"
cd "$SEED"
mkdir -p data notes
cat > README.md <<'MD'
# Tarrow Field Ledger

Nightly mirror of the field-station observation ledger.
Mirrored over SSH to the on-prem git service.
MD
cat > data/fields.csv <<'CSV'
plot,observed_at,reading_c
A1,2031-04-01T06:00:00Z,-2.5
A1,2031-04-02T06:00:00Z,-1.1
B2,2031-04-01T06:00:00Z,0.4
B2,2031-04-02T06:00:00Z,1.9
CSV
git add -A
git commit -q -m "seed field ledger"
cat > notes/survey-01.md <<'MD'
Survey 01: snow pack receding on the north transect.
Probe B2 partially submerged; relocate before thaw.
MD
git add -A
git commit -q -m "add survey notes"
git push -q "$SRV/ledger.git" main
rm -rf "$SEED"

# ------------------------------------------------------------- empty.git (hidden)
# Unborn HEAD -> master (matches the client default a clone falls back to for
# an empty repository, so the sync's pushed branch is deterministic).
git init -q --bare -b master "$SRV/empty.git"

# ------------------------------------------------------------- legacy.git (hidden)
seed_repo "$SRV/legacy.git" master
SEED=$(mktemp -d)
git init -q -b master "$SEED"
cd "$SEED"
cat > README.md <<'MD'
Legacy ledger import (2019). Superseded by the field ledger but still
served for archival audits. Do not rewrite the format.
MD
printf 'stale manifest from 2019\n' > manifest.txt
git add -A
git commit -q -m "initial legacy import"
git push -q "$SRV/legacy.git" master
rm -rf "$SEED"

# ------------------------------------------------------------- quartz.git (hidden)
seed_repo "$SRV/quartz.git" main
SEED=$(mktemp -d)
git init -q -b main "$SEED"
cd "$SEED"
mkdir -p sensors
cat > sensors/instruments.log <<'LOG'
2031-02-01T00:00:00Z quartz-A ok
2031-02-01T06:00:00Z quartz-B ok
LOG
git add -A
git commit -q -m "quartz sensor bootstrap"
git push -q "$SRV/quartz.git" main
rm -rf "$SEED"

chown -R root:root "$SRV"
