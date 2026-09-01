#!/bin/bash
# build_fixtures.sh - creates the compromised SSH-served remote bare repository
# for the "umber-yonder" git-forensics task. Runs at image build time.
#
# The remote holds a small static publication repo whose history contains:
#   * a committed API key (the leak to EXPUNGE) in config/deploy.env and in a
#     later commit message,
#   * a committed-then-deleted retry credential (the "recovery secret") that
#     survives only in a superseded, still-reachable old blob.
set -euo pipefail

export GIT_AUTHOR_NAME="Roon Desi"
export GIT_AUTHOR_EMAIL="roon@paloma.example"
export GIT_COMMITTER_NAME="Roon Desi"
export GIT_COMMITTER_EMAIL="roon@paloma.example"
export GIT_CONFIG_NOSYSTEM=1

BARE=/srv/git/paloma.git
mkdir -p /srv/git

# Build history in a throwaway working clone, then push into the bare remote.
SEED=$(mktemp -d)
git init -q -b main "$SEED"
git -C "$SEED" config user.name  "Roon Desi"
git -C "$SEED" config user.email "roon@paloma.example"
cd "$SEED"
mkdir -p src .github/workflows config notes

# ---------------------------------------------------------------- C1 scaffold
cat > README.md <<'MD'
# Paloma Studio

Repository for the Paloma Studio publication site and its build pipeline.
MD

cat > src/publish.py <<'PY'
VERSION = "0.3.1"

def publish(api):
    return {"version": VERSION, "key": api}

if __name__ == "__main__":
    import os
    print(publish(os.environ.get("PALOMA_API_KEY", "unset")))
PY

cat > .github/workflows/deploy.yml <<'YML'
name: paloma-deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: python3 src/publish.py
YML

cat > config/deploy.env <<'ENV'
PALOMA_API_KEY=PLATA-9B2F-CA14
PALOMA_REGION=eu-central-1
ENV

cat > notes/editorial.md <<'MD'
Editorial calendar for Q3. Pages build on the first of each month.
MD

git add -A
git commit -q -m "scaffold paloma studio publication"

# ---------------------------------------------------------------- C2 roster (secret)
cat > notes/roster.list <<'RO'
name,role,token
Mira,writer,SURF:81a2cf4d
Elfer,editor,ok
RO
git add notes/roster.list
git commit -q -m "add shared roster notes"

# ---------------------------------------------------------------- C3 delete roster
git rm -q notes/roster.list
git commit -q -m "retire roster notes; keep credentials in the vault"

# ---------------------------------------------------------------- C4 bump + leak in msg
cat > src/publish.py <<'PY'
VERSION = "0.4.2"

def publish(api):
    return {"version": VERSION, "key": api}

if __name__ == "__main__":
    import os
    print(publish(os.environ.get("PALOMA_API_KEY", "unset")))
PY
git add src/publish.py
git commit -q -m "ship 0.4.2 with PLATA-9B2F-CA14"

# Push every ref into the bare remote and discard the scratch clone.
git init -q --bare "$BARE"
git -C "$SEED" push -q "$BARE" main
# Point the bare remote's HEAD at the branch we shipped.
git -C "$BARE" symbolic-ref HEAD refs/heads/main
rm -rf "$SEED"

echo "fixture remote ready at $BARE"
