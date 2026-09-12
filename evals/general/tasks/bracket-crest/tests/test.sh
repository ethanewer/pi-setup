#!/bin/bash
# bracket-crest verifier.
#
# Grades the agent's fix of the prettier/prettier Markdown setext-in-
# blockquote bug at /app/src:
#   (0) leak guard: the upstream fix commit object must not be reachable
#       from the agent's clone (it was never fetched into /app/src)
#   (0b) tooling integrity: every binary the verifier runs comes from a
#       build-time mirror /opt/pi-tools or from /usr/bin:/bin; /usr/local/bin
#       (a user-writable path) is excluded from PATH so that wrapper scripts
#       planted there can never intercept grading calls. PATH poisoning via
#       NODE_OPTIONS / NODE_PATH / BASH_ENV / ENV is neutralised up front.
#   (1) provenance: relative to the pinned parent commit, only
#       src/language-markdown/print/preprocess.js may differ. Tracker bit
#       tricks (git update-index --assume-unchanged / --skip-worktree, which
#       hide modified tracked files from status/diff) are neutralised first by
#       clearing those bits and refreshing the index; the three files that
#       carry the grading path (bin/prettier.js, bin/prettier.cjs,
#       jest.config.js) are additionally compared content-wise against the
#       parent blobs, which does not consult the index at all.
#   (2) the user-facing repro through the project's own CLI: formatting the
#       reported input must return it byte-for-byte unchanged
#   (2b) golden integrity: /opt/golden/setext (extracted from the upstream
#       fix commit at image build) must still byte-match the fix-commit
#       fixture, checked against SHA-256 constants embedded HERE, in this
#       script. This file lives on the fresh /tests mount, so the hashes are
#       outside the agent's reach and cannot be overwritten or widened.
#   (2c) jest integrity: node_modules/.bin/jest and the node_modules/jest*
#       tree must still hash to the manifest recorded at image build; a
#       replaced/fake jest (which would make both jest-based stages vacuous)
#       is detected before any suite runs.
#   (3) the project's own regression test for the bug, the Markdown setext
#       suite tests/format/markdown/heading/setext/ at the upstream FIX
#       commit (extracted to /opt/golden at image build time), must pass
#       against the agent's tree with the project's own jest runner
#   (4) the project's own whole Markdown format suite (tests/format/markdown,
#       including the golden setext suite) must still pass
#   (5) authored hidden cases exercising the same code path through the
#       project's own CLI with inputs the upstream regression fixture does
#       not use must pass
#
# Writes 0/1 to /logs/verifier/reward.txt on every path (the EXIT trap covers
# any path that raises before writing).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u

# --- tooling integrity: never consult /usr/local/bin, never trust env vars ---
export PATH="/opt/pi-tools:/usr/bin:/bin"
unset NODE_OPTIONS NODE_PATH BASH_ENV ENV 2>/dev/null || true

mkdir -p /logs/verifier

PARENT=45a4a75ea639e69d35f885224818e6698561fc11
FIX=07184252aa4a84fcc542f34e5e70291a08b5de3a
JEST=/app/src/node_modules/.bin/jest
FAILS=0

# Grading-critical tracked files, compared against the parent BLOBS (no
# reliance on the index, so --assume-unchanged / --skip-worktree cannot hide
# tampering with them).
CRITICAL_FILES="bin/prettier.js bin/prettier.cjs jest.config.js"

# SHA-256 of the /opt/golden/setext fixture files, as extracted from the
# upstream fix commit 07184252a (computed from the fix-commit bytes; this
# script is delivered on the fresh /tests mount, so an agent cannot rewrite
# these constants).
GOLDEN_SHA256=$(cat <<'EOF'
__snapshots__/format.test.js.snap a265453bc14361ebadd71e8b131f0cc3ac8637fb423088862d3f9dbc402b6e96
blockquote.md 6caeb9a537641d6c572ab74cf4f7c74bb2f5fe6724c641b4710e90c1ab557526
child.md 29ba693387e38959bfc540a43c8c9cf232b6722ca708ef8b5156cb67081e6440
definition-before.md 72a3ef9706430e29f56666945b11130c2560d065f8337afd5783823667874baf
format.test.js cc4e53858fe10d6b87b4aeeb1e29d38806d1812ebb0810ce12f4d6b7ba2a54e5
issue-19148.md 7dfa12b39b3ae406ee31cc72fe7f78c9091e5520bd1deeba6cb13570ccdaff2b
issue-6013-2.md 82394c8ab6de973d4081712fa4f0094910486a0a07dad96c6d0b4cc82eb83884
issue-6013.md c6cafd6c5bce76683e52efabc44290c82bedb753c26eaec92ebcbbcb9f6b33dc
not-header.md c7da90203106b7743c9808d72e7cb58fe2c0b7d8319263a8861429e5ccba72d9
setext.md d5674672ff2d9277f6133c3aa9591da9cd91f78c0f1b6fa1ba2b84c15e43113a
EOF
)

cd /app/src || { echo "FAIL: /app/src missing"; echo 0 > /logs/verifier/reward.txt; exit 0; }

if [ ! -x "$JEST" ]; then
    echo "FAIL: jest not installed under /app/src/node_modules"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

# ---------------------------------------------------------------------------
# (0) leak guard: the fix commit must not be reachable from the agent's clone
# ---------------------------------------------------------------------------
if git cat-file -e "$FIX^{commit}" 2>/dev/null; then
    echo "FAIL [leak-guard] the upstream fix commit object is present in /app/src"
    FAILS=$((FAILS + 1))
else
    echo "PASS [leak-guard] fix commit object absent from /app/src"
fi

# ---------------------------------------------------------------------------
# (0b) tooling integrity: the verifier's own binaries must be the ones the
# image was built with; nothing may come from /usr/local/bin (an agent-
# writable path). Detects wrapper planting ("fake node/diff/git" attacks).
# ---------------------------------------------------------------------------
tooling_ok=1
for t in node git diff sha256sum cmp timeout cp sed sort find tail grep mkdir cat rm tr cut; do
    if ! command -v "$t" >/dev/null 2>&1; then
        echo "FAIL [tooling] $t missing from trusted PATH"
        tooling_ok=0
    elif case "$(command -v "$t")" in /usr/local/bin/*) true;; *) false;; esac; then
        echo "FAIL [tooling] $t resolves into /usr/local/bin ($(command -v "$t" 2>/dev/null))"
        tooling_ok=0
    fi
done
if [ "$tooling_ok" = 1 ]; then
    echo "PASS [tooling] all grading tools resolve outside /usr/local/bin"
else
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (1) provenance: the upstream tree must be unmodified except
#     src/language-markdown/print/preprocess.js
# ---------------------------------------------------------------------------
provenance_ok=1
if [ "$(git rev-parse HEAD 2>/dev/null)" = "$PARENT" ]; then
    :
elif git cat-file -e "$PARENT^{commit}" 2>/dev/null; then
    # agent committed its work: tree diff vs the parent still decides
    :
else
    echo "FAIL [provenance] parent commit $PARENT not present in the clone"
    provenance_ok=0
fi

# Neutralise tracker-bit tricks: clear --assume-unchanged and --skip-worktree
# on every entry that carries them (those flags make git skip the worktree
# hash, hiding modified tracked files from diff/status), then refresh stat.
tracked_bits=$(git ls-files -v 2>/dev/null | awk '$1 ~ /^[hHsS]/ {print $2}')
if [ -n "$tracked_bits" ]; then
    for f in $tracked_bits; do
        git update-index --no-assume-unchanged --no-skip-worktree "$f" >/dev/null 2>&1 || true
    done
fi
git update-index -q --refresh 2>/dev/null || true

changed=$(git diff --name-only "$PARENT" 2>/dev/null)
for f in $changed; do
    if [ "$f" != "src/language-markdown/print/preprocess.js" ]; then
        echo "FAIL [provenance] upstream file differs from the parent: $f"
        provenance_ok=0
    fi
done
entries=$(git status --porcelain 2>/dev/null | sed 's/^...//' | sort -u)
for f in $entries; do
    if [ "$f" != "src/language-markdown/print/preprocess.js" ]; then
        echo "FAIL [provenance] unexpected working-tree entry: $f"
        provenance_ok=0
    fi
done

# Index-independent content check of the grading-critical tracked files.
for cf in $CRITICAL_FILES; do
    if ! git show "$PARENT:$cf" 2>/dev/null | cmp -s - "$cf"; then
        echo "FAIL [provenance] $cf differs from the parent blob (index-independent check)"
        provenance_ok=0
    fi
done
if [ "$provenance_ok" = 1 ]; then
    echo "PASS [provenance] tree unmodified except src/language-markdown/print/preprocess.js"
else
    echo "FAIL [provenance] tree audit failed (see lines above)"
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (2) user-facing repro through the project's own CLI: the reported input
#     must be formatted back byte-for-byte unchanged. The input is rebuilt
#     here so the check cannot be satisfied by editing files on disk.
# ---------------------------------------------------------------------------
printf '> Multi\n> Line\n> ===\n' > /tmp/crest_repro.md
if timeout 60 node bin/prettier.js /tmp/crest_repro.md > /tmp/crest_repro.out 2>&1 \
        && diff -q /tmp/crest_repro.md /tmp/crest_repro.out >/dev/null; then
    echo "PASS [repro] node bin/prettier.js formats the reported input back unchanged"
else
    echo "FAIL [repro] formatting the reported input does not return it unchanged"
    echo "--- got ---"
    cat /tmp/crest_repro.out 2>/dev/null
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (2b) golden integrity: the /opt/golden/setext fixture (extracted from the
#      upstream fix commit at image build) must byte-match the fix-commit
#      bytes. Constants are embedded above (this script ships on the fresh
#      /tests mount, so an agent cannot rewrite them). Catches replacing or
#      editing the golden fixture to make the regression test vacuous.
# ---------------------------------------------------------------------------
golden_ok=1
golden_count=0
while read -r gf gh; do
    [ -n "$gf" ] || continue
    golden_count=$((golden_count + 1))
    got=$(sha256sum "/opt/golden/setext/$gf" 2>/dev/null | cut -d' ' -f1)
    if [ "$got" != "$gh" ]; then
        echo "FAIL [golden-integrity] /opt/golden/setext/$gf hash mismatch (got $got want $gh)"
        golden_ok=0
    fi
done <<EOF
$GOLDEN_SHA256
EOF
if [ "$golden_count" -ne 10 ]; then
    echo "FAIL [golden-integrity] expected 10 golden files, found $golden_count"
    golden_ok=0
fi
[ "$golden_ok" = 1 ] && echo "PASS [golden-integrity] /opt/golden/setext byte-matches the fix-commit fixture" \
                   || { echo "FAIL [golden-integrity] golden fixture tampered"; FAILS=$((FAILS + 1)); }

# ---------------------------------------------------------------------------
# (2c) jest integrity: the jest runner and its package tree must hash to the
#      manifest recorded at image build (same computation as the Dockerfile).
#      A fake/replaced jest makes both jest-based stages below vacuous.
# ---------------------------------------------------------------------------
if [ ! -s /opt/golden/jest.sha256 ]; then
    echo "FAIL [jest-integrity] build-time jest manifest missing at /opt/golden/jest.sha256"
    FAILS=$((FAILS + 1))
else
    want=$(cat /opt/golden/jest.sha256)
    got=$(
        { find node_modules/jest node_modules/jest-* node_modules/@jest -type f 2>/dev/null | LC_ALL=C sort | xargs -r sha256sum; \
          sha256sum node_modules/.bin/jest 2>/dev/null; } | sha256sum | cut -d' ' -f1
    )
    if [ "$got" = "$want" ]; then
        echo "PASS [jest-integrity] jest runner byte-matches the image-build manifest"
    else
        echo "FAIL [jest-integrity] jest runner differs from the image-build manifest"
        echo "  want $want"
        echo "  got  $got"
        FAILS=$((FAILS + 1))
    fi
fi

# ---------------------------------------------------------------------------
# (3) golden: the upstream regression suite from the fix commit, run in the
#     project's own tree with the project's own jest runner. The setext
#     fixtures are byte-identical between the two commits except for
#     blockquote.md and its snapshot, so copying the fix-commit directory in
#     (which also carries the blockquote.md regression fixture) is exact.
# ---------------------------------------------------------------------------
mkdir -p tests/format/markdown/heading/setext
cp -r /opt/golden/setext/. tests/format/markdown/heading/setext/
if [ -f /opt/golden/setext/blockquote.md ] \
        && timeout 300 "$JEST" tests/format/markdown/heading/setext --config jest.config.js --runInBand > /tmp/crest_golden.out 2>&1; then
    echo "PASS [golden] upstream setext suite (incl. blockquote.md fixture) green"
else
    echo "FAIL [golden] upstream setext suite (incl. blockquote.md fixture) not green"
    tail -n 40 /tmp/crest_golden.out 2>/dev/null
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (4) the project's own Markdown format suite (includes the golden setext
#     suite copied above): must still be green
# ---------------------------------------------------------------------------
if timeout 420 "$JEST" tests/format/markdown --config jest.config.js --runInBand > /tmp/crest_md.out 2>&1; then
    echo "PASS [suite] project Markdown format suite (tests/format/markdown) green"
else
    echo "FAIL [suite] project Markdown format suite (tests/format/markdown) not green"
    tail -n 40 /tmp/crest_md.out 2>/dev/null
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (5) authored hidden cases through the project's own CLI (setext headings
#     inside blockquotes with inputs the upstream fixture does not use:
#     3-line '=' headings, '-' underlines, nested '> >' blockquotes, very
#     long text lines). Each case must format to its expected bytes.
# ---------------------------------------------------------------------------
hidden_ok=1
i=1
found=0
for dir in /tests/hidden/*/; do
    input="$dir"input.md
    expected="$dir"expected.md
    [ -f "$input" ] || continue
    [ -f "$expected" ] || continue
    found=$((found + 1))
    if timeout 60 node bin/prettier.js "$input" > /tmp/crest_h${i}.out 2>&1 \
            && diff -q "$expected" /tmp/crest_h${i}.out >/dev/null; then
        echo "PASS [hidden $i] $dir"
    else
        echo "FAIL [hidden $i] $dir"
        echo "--- expected ---"
        cat "$expected"
        echo "--- got ---"
        cat /tmp/crest_h${i}.out 2>/dev/null
        hidden_ok=0
    fi
    i=$((i + 1))
done
if [ "$found" -lt 2 ]; then
    echo "FAIL [hidden] expected at least 2 hidden cases, found $found"
    FAILS=$((FAILS + 1))
fi
[ "$hidden_ok" = 1 ] || { echo "FAIL [hidden] one or more hidden cases failed"; FAILS=$((FAILS + 1)); }

# ---------------------------------------------------------------------------
# verdict (binary)
# ---------------------------------------------------------------------------
if [ "$FAILS" = 0 ]; then
    echo "REWARD 1: leak-guard + tooling + provenance + repro + golden-integrity + jest-integrity + golden suite + Markdown suite + hidden cases all green"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $FAILS check(s) failed"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0