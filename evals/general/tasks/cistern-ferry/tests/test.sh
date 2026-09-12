#!/bin/bash
# cistern-ferry verifier.
#
# Grades the agent's fix of the prettier/prettier HTML attribute-casing bug
# at /app/src:
#   (0) leak guard: the upstream fix commit object must not be reachable
#       from the agent's clone (it was never fetched into /app/src)
#   (1) provenance: relative to the pinned parent commit, only
#       src/language-html/parse/postprocess.js may differ (untracked files
#       included)
#   (2) the user-facing repro through the project's own CLI: formatting the
#       reported input must lowercase the attribute name on both the span
#       (no per-element data) and the div (has per-element data)
#   (3) the project's own existing HTML suites (attributes, case, basics,
#       tags + the html-elements unit test) must still pass with the
#       project's own jest runner
#   (4) the project's own regression test from the upstream FIX commit,
#       tests/format/html/attributes/lowercase/ (extracted to /opt/golden at
#       image build time), must pass against the agent's tree
#   (5) authored hidden cases exercising the same code path through the
#       project's own CLI with inputs the upstream regression test does not
#       use must pass
#
# Writes 0/1 to /logs/verifier/reward.txt on every path (the EXIT trap covers
# any path that raises before writing).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

PARENT=7c5872f7a27b3eb249d0347fcfac989eca2cb70b
FIX=bfb1eacd89ba5b3b6fd5f2faf7908da8bbd558a2
JEST=/app/src/node_modules/.bin/jest
FAILS=0

cd /app/src || { echo "FAIL: /app/src missing"; echo 0 > /logs/verifier/reward.txt; exit 0; }

if [ ! -x "$JEST" ]; then
    echo "FAIL: jest not installed under /app/src/node_modules"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

# ---------------------------------------------------------------------------
# (0.5) image integrity: the authored artifacts the checks below depend on
# (the reproducer, the fix-commit golden test extracted to /opt/golden at
# build time, the @prettier/html-* data packages the HTML parser loads, and
# the jest entry point) must still be the bytes this image was built with.
# The trial runs in the same container as the agent, so these files live on
# the agent's writable filesystem; a "fix" that works by rewriting any of
# them instead of the tracked source is not a fix.
# ---------------------------------------------------------------------------
integrity_fail() {
    echo "FAIL [integrity] $1"
    echo "  the trial image was modified in a way the verifier cannot accept: $2"
    echo "  reward 0"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

check_sha() {  # path expected
    [ -f "$1" ] || integrity_fail "missing $1" "$1 does not exist"
    actual=$(sha256sum "$1" | cut -d' ' -f1)
    [ "$actual" = "$2" ] || integrity_fail "bad checksum for $1" \
        "expected $2 got $actual"
}

check_sha /app/reproduce.js c1fd02aac903e6fd73c8ffb5298a3507b1090ea73b1a3f575d4d693e04e8c345
check_sha /opt/golden/lowercase/format.test.js 6c13bfc5eb0595e1d08d5428f0b09525bb81fc851d1bea68a02c076d9d826be9
check_sha /opt/golden/lowercase/__snapshots__/format.test.js.snap 6305ac9696995c5dfdf8273a225f8a8fc245014cf9d971394c9fb7f937c064cf
check_sha /app/src/node_modules/@prettier/html-attributes/element.json cf55b88eb00eefbd9afafa05677cee9a3e0e9aa60721e3eecf7d09d4400c473b
check_sha /app/src/node_modules/@prettier/html-attributes/global.json d9ebe3682dbac41468154adddb9a6e87c63596770453ba149622c411b241582f
check_sha /app/src/node_modules/@prettier/html-attributes/index.js 582a60fd2fd6d8d6a5a72d78ca24ec0caa7fc2aaeca2860a7169d7aa8cc23a35
check_sha /app/src/node_modules/@prettier/html-attributes/package.json 95d11242f364c9034bff840e63c48f63713aae0650d66bc51ff1419f07a80d21
check_sha /app/src/node_modules/@prettier/html-tags/html-tags.json ec9fe9f9dde9f224c413f0667b55c11ed2e55be747a0e9ae2a8b12a9a1b4a774
check_sha /app/src/node_modules/@prettier/html-tags/html-void-tags.json f23ca636ea818f567bd4a7490faf78ce87fac9a6ac9b2f2473dd60161be05f2d
check_sha /app/src/node_modules/@prettier/html-tags/index.js 43c01538e37514431999ed286c001e97f5d8f7c7d14bb93c9b2bb74da29d4817
check_sha /app/src/node_modules/@prettier/html-tags/index.json bb489fa43e1717d3ba95872d9daf4ac6390f4fa1d17da18570bb6bbfe771cc21
check_sha /app/src/node_modules/@prettier/html-tags/package.json 36ff4146593f123dc916069943d1d85fd64dee127dd9486c65f660bb4c258f4d
check_sha /app/src/node_modules/.bin/jest 2a9b435eab8a343bd09fe285b2e2043ff9ff89fae4e1d1f46ba3df28659d8a2c
echo "PASS [integrity] authored artifacts and node_modules data packages byte-identical to build time"

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
# (1) provenance: the upstream tree must be unmodified except
#     src/language-html/parse/postprocess.js
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
changed=$(git diff --name-only "$PARENT" 2>/dev/null)
for f in $changed; do
    if [ "$f" != "src/language-html/parse/postprocess.js" ]; then
        echo "FAIL [provenance] upstream file differs from the parent: $f"
        provenance_ok=0
    fi
done
entries=$(git status --porcelain 2>/dev/null | sed 's/^...//' | sort -u)
for f in $entries; do
    if [ "$f" != "src/language-html/parse/postprocess.js" ]; then
        echo "FAIL [provenance] unexpected working-tree entry: $f"
        provenance_ok=0
    fi
done
if [ "$provenance_ok" = 1 ]; then
    echo "PASS [provenance] tree unmodified except src/language-html/parse/postprocess.js"
else
    echo "FAIL [provenance] tree audit failed (see lines above)"
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (2) user-facing repro through the project's own CLI
# ---------------------------------------------------------------------------
repro_ok=1
if timeout 120 node /app/reproduce.js > /tmp/cf_repro.out 2>&1; then
    :
else
    repro_ok=0
fi
if grep -q 'class="should print as lowercase">text</span>' /tmp/cf_repro.out \
        && grep -q 'class="should print as lowercase">text</div>' /tmp/cf_repro.out \
        && ! grep -q 'CLASS' /tmp/cf_repro.out; then
    echo "PASS [repro] /app/reproduce.js lowercases the attribute on both tags"
    cat /tmp/cf_repro.out
else
    echo "FAIL [repro] /app/reproduce.js did not lowercase the attribute on both tags"
    cat /tmp/cf_repro.out 2>/dev/null
    repro_ok=0
fi
[ "$repro_ok" = 1 ] || FAILS=$((FAILS + 1))

# ---------------------------------------------------------------------------
# (3) the project's own existing HTML suites with its own jest runner
# ---------------------------------------------------------------------------
if timeout 420 "$JEST" tests/format/html/attributes tests/format/html/case tests/format/html/basics tests/format/html/tags tests/unit/html-elements.js --config jest.config.js --runInBand > /tmp/cf_suite.out 2>&1; then
    echo "PASS [suite] project HTML suites (attributes, case, basics, tags, html-elements) green"
else
    echo "FAIL [suite] project HTML suites not green"
    tail -n 40 /tmp/cf_suite.out 2>/dev/null
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (4) golden: the upstream regression lowercase suite from the fix commit,
#     run in the project's own tree with the project's own jest runner
# ---------------------------------------------------------------------------
mkdir -p tests/format/html/attributes/lowercase
cp -r /opt/golden/lowercase/. tests/format/html/attributes/lowercase/
if timeout 300 "$JEST" tests/format/html/attributes/lowercase/format.test.js --config jest.config.js --runInBand > /tmp/cf_golden.out 2>&1; then
    echo "PASS [golden] upstream lowercase regression suite (snippet '#0 format 1') green"
else
    echo "FAIL [golden] upstream lowercase regression suite not green"
    tail -n 40 /tmp/cf_golden.out 2>/dev/null
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (5) authored hidden cases through the project's own CLI: attribute-name
#     normalization on inputs the upstream lowercase test does not use
# ---------------------------------------------------------------------------
hidden_ok=1
i=1
found=0
for dir in /tests/hidden/*/; do
    input="$dir"input.html
    expected="$dir"expected.html
    [ -f "$input" ] || continue
    [ -f "$expected" ] || continue
    found=$((found + 1))
    if timeout 60 node bin/prettier.js "$input" > /tmp/cf_h${i}.out 2>&1 \
            && diff -q "$expected" /tmp/cf_h${i}.out >/dev/null; then
        echo "PASS [hidden $i] $dir"
    else
        echo "FAIL [hidden $i] $dir"
        echo "--- expected ---"
        cat "$expected"
        echo "--- got ---"
        cat /tmp/cf_h${i}.out 2>/dev/null
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
    echo "REWARD 1: leak-guard + provenance + repro + HTML suites + golden regression + hidden cases all green"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $FAILS check(s) failed"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0