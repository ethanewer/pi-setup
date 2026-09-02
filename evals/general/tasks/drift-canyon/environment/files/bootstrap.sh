#!/bin/bash
# bootstrap.sh — builds the mangled "drift-canyon" fixtures that a candidate
# agent must repair/assemble. Only runs at image build time.
set -euo pipefail

export GIT_AUTHOR_NAME="Marlow Bayne"
export GIT_AUTHOR_EMAIL="marlow@example.net"
export GIT_COMMITTER_NAME="Marlow Bayne"
export GIT_COMMITTER_EMAIL="marlow@example.net"

# ---------------------------------------------------------------------------
# 1. Raw bio notes that form the seed for the personal profile website.
# ---------------------------------------------------------------------------
mkdir -p /app/notes/posts /app/bundles

cat > /app/notes/bio.md <<'EOF'
Marlow Bayne
Tidal-field ecologist who left a comfortable lab job to live above a boatworks.
Studies barnacle recruitment in the intertidal zone and keeps a running photo log.
EOF

cat > /app/notes/posts/ember.md <<'EOF'
Into the Ember Mud
A long spring walk over the salt flats a night after the diggers left;
everything came up rust-red at low water.
EOF

cat > /app/notes/posts/harbor.md <<'EOF'
Harbor at Low Water
Notes on the mooring grid when the chart was wrong, and how the barnacles
reasserted the original shoreline by autumn.
EOF

cat > /app/notes/pubs.md <<'EOF'
Bayne, M. 2019. Settlement near the high-water mark: a year of quadrat counts.
Intertidal Letters, 12, 41-56.
Bayne, M. & Okonkwo, R. 2021. Recruitment windows reconstructed from archived
shoreline photos. Coastal Methods, 4, 118-133.
EOF

# A short personal plan the agent should leave untouched (part of listing.txt).
printf 'Keep the site tiny. Ship the notes as pages. Serve it from home.\n' > /app/personal-plan.txt

# ---------------------------------------------------------------------------
# 2. The mangled working repository at /app/site.
# ---------------------------------------------------------------------------
mkdir -p /app/site
cd /app/site
git init -q -b main
git config user.name "Marlow Bayne"
git config user.email "marlow@example.net"

mkdir -p deploy notes/posts

cp /app/notes/bio.md notes/bio.md
cp /app/notes/posts/ember.md notes/posts/ember.md
cp /app/notes/posts/harbor.md notes/posts/harbor.md
cp /app/notes/pubs.md notes/pubs.md
cp /app/personal-plan.txt personal-plan.txt

# A provided legacy rebuild script that must be made executable but not edited.
cat > deploy/reconstruct.sh <<'RS'
#!/bin/sh
# Rebuild the Marlow profile site pages under OUT from the notes under NOTES.
# Left non-executable on purpose: the reconstruction script's executable bit
# is the last thing to be restored before the site can be shipped.
set -eu
NOTES_DIR="${1:-/app/notes}"
OUT_DIR="${2:-/app/site}"
python3 - "$NOTES_DIR" "$OUT_DIR" <<'PY'
import os, sys
notes, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
bio = open(os.path.join(notes, "bio.md")).read()
(open(os.path.join(out, "reconstructed.txt"), "w").write(bio))
PY
echo "site reconstructed"
RS
chmod 644 deploy/reconstruct.sh

git add -A
git commit -q -m "seed: raw notes and the non-executable rebuild script"

# ---------------------------------------------------------------------------
# 3. Lost / off-branch uncommitted work: a stash holding a story draft that is
#    not present on 'main'.  The agent must locate and restore it to main.
# ---------------------------------------------------------------------------
mkdir -p writing/sketches
printf 'The cove lantern, lit early on the night the storm gauge failed.\n' \
    > /app/site/writing/sketches/story-notes.txt
cd /app/site
git add writing/sketches/story-notes.txt
git stash push -q -m "sidecar story draft (lost)" -- writing/sketches/story-notes.txt
# After the stash the working tree no longer contains the file.
rm -f writing/sketches/story-notes.txt

# ---------------------------------------------------------------------------
# 4. Two git bundles carrying one branch each for the bundle-head checkout.
# ---------------------------------------------------------------------------
TMPA=$(mktemp -d)
TMPB=$(mktemp -d)

git -C "$TMPA" init -q -b main
git -C "$TMPA" config user.name "Marlow Bayne"
git -C "$TMPA" config user.email "marlow@example.net"
mkdir -p "$TMPA/blog"
printf '<h1>Into the Ember Mud</h1><p>Wet by rust-colored low water.</p>\n' > "$TMPA/blog/on-guide.html"
git -C "$TMPA" add -A
git -C "$TMPA" commit -q -m "on-guide post"
git -C "$TMPA" branch -M on-guide
git -C "$TMPA" bundle create /app/bundles/on-guide.bundle --all

git -C "$TMPB" init -q -b main
git -C "$TMPB" config user.name "Marlow Bayne"
git -C "$TMPB" config user.email "marlow@example.net"
mkdir -p "$TMPB/blog"
printf '<h1>Harbor at Low Light</h1><p>The mooring grid under a chart that lied.</p>\n' > "$TMPB/blog/fieldnotes.html"
git -C "$TMPB" add -A
git -C "$TMPB" commit -q -m "fieldnotes post"
# Nested ref name on purpose: the branch must be reconstructed from the HEAD
# reference (or by inspecting the bundle's refs), not from a flat ref name.
git -C "$TMPB" branch -M prospect/fieldnotes
git -C "$TMPB" bundle create /app/bundles/fieldnotes.bundle --all

rm -rf "$TMPA" "$TMPB"

# ---------------------------------------------------------------------------
# 5. The source listing that must be preserved byte-for-byte.
# ---------------------------------------------------------------------------
cat > /app/listing.txt <<'EOF'
deploy/reconstruct.sh
notes/bio.md
notes/posts/ember.md
notes/posts/harbor.md
notes/pubs.md
personal-plan.txt
writing/sketches/story-notes.txt
site/README.md
EOF

# Seed the site repo with a README after construction (part of the product).
printf '# Marlow Bayne — personal profile\n' > /app/site/README.md

# ---------------------------------------------------------------------------
# 6. NOTE: the serving user (gitdev), its password, /srv/git and the bare
# repository are NOT set up here.  Standing up the SSH password-auth git server
# (dedicated OS user, bare repo, password login) is part of the candidate's
# deliverable and must be created by the reconstruction script, not the image.
# The container is therefore pristine with respect to the served server.

echo "bootstrap complete"