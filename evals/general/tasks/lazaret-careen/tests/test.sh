#!/bin/bash
# Verifier for lazaret-careen. On the agent's final tree at /app/src:
# (1) provenance — HEAD still the pinned parent commit, every tracked file
#     except networkx/readwrite/gml.py byte-identical to the parent blobs,
#     no untracked non-ignored files;
# (2) deliverables — /app/summary.md non-empty; /app/reproduce.py present
#     and self-contained (it must not reach into /app, /tests, /opt,
#     /solution or /logs paths);
# (3) the agent's OWN reproduction runs BOTH ways: it must FAIL (non-zero)
#     against a pristine pre-fix snapshot of the parent tree, and PASS
#     against the /app/src tree being graded;
# (4) fix present in the graded TREE's source (generate_gml's tuple-label
#     branch routes the label through the same escape() the string branch
#     uses; read from the actual file, not from any import);
# (5) plant the upstream regression test (golden test_gml.py, extracted
#     from the fix commit at image build time; never part of this task
#     tree) and run the whole networkx/readwrite/tests/ directory — the
#     golden regression test must have actually run and passed, and the
#     project's other readwrite tests must stay green;
# (6) three authored hidden cases exercising the same tuple-label escape
#     path from inputs the upstream test does not use (3-tuple with quote+
#     edge fragment, quote+node fragment through write_gml/read_gml,
#     mixed-type label with backslash+quote).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=b1f956344071ba1adfad17d56d62a7a78dfd37e6
ALLOWED=networkx/readwrite/gml.py

# Run every Python decision of this verifier in a site-independent process.
# The agent phase runs as root with site-packages writable, so an agent
# could otherwise plant a sitecustomize.py that intercepts generate_gml at
# interpreter startup and make every test pass while leaving the buggy tree
# at /app/src untouched. `python3 -S` skips the site module entirely (no
# sitecustomize import, no .pth processing); networkx resolves to a tree of
# our choosing via an explicit PYTHONPATH.
SP=$(python3 -c 'import site; print(site.getsitepackages()[0])')

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    is in. Content check (hash the actual bytes against the parent blobs),
#    so assume-unchanged/skip-worktree tricks cannot hide a dirty file; any
#    untracked non-ignored file is refused too.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        "$ALLOWED") : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                have=$(readlink "$f")
                want_cont=$(git cat-file blob "$want" 2>/dev/null || true)
                if [ "$have" != "$want_cont" ]; then
                    echo "out-of-scope modified symlink target: $f ('$have' != '$want_cont')" >> "$LOG"; ok=0
                fi
                continue
            fi
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverables: change summary, and the agent's own reproduction.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
[ -f /app/reproduce.py ] || fail "/app/reproduce.py is missing"
if grep -nE '(/app|/tests|/opt/|/solution|/logs)' /app/reproduce.py > /tmp/repro_paths.txt 2>&1; then
    head -5 /tmp/repro_paths.txt
    fail "/app/reproduce.py must be self-contained: it may not reference /app, /tests, /opt, /solution or /logs paths"
fi

# 3b) the reproduction must FAIL against a pristine pre-fix snapshot of the
#     parent tree. Materialise that snapshot from the pinned commit object
#     itself (git archive of HEAD — the committed tree, never the agent's
#     working tree), so this cannot be satisfied by pointing the repro at
#     a fixed copy.
rm -rf /tmp/prefix && mkdir -p /tmp/prefix
rm -rf /tmp/run-pre && mkdir -p /tmp/run-pre
git archive --format=tar HEAD | tar -x -C /tmp/prefix || fail "cannot materialise pristine parent tree"
if ! ( cd /tmp/run-pre && PYTHONPATH="/tmp/prefix:$SP" python3 -S /app/reproduce.py ) > /tmp/repro_prefix.out 2>&1; then
    echo "reproduce.py failed on the pristine pre-fix tree as required"
    tail -4 /tmp/repro_prefix.out | sed 's/^/    pre-fix: /'
else
    cat /tmp/repro_prefix.out
    fail "reproduce.py PASSED on the pristine pre-fix tree: it does not demonstrate the bug"
fi

# 3c) and the SAME reproduction must PASS against the tree being graded at
#     /app/src (run from a neutral cwd in the site-independent interpreter,
#     so a repro that writes scratch files cannot dirty the tree).
rm -rf /tmp/run-fixed && mkdir -p /tmp/run-fixed
if ( cd /tmp/run-fixed && PYTHONPATH="/app/src:$SP" python3 -S /app/reproduce.py ) > /tmp/repro_fixed.out 2>&1; then
    cat /tmp/repro_fixed.out
else
    cat /tmp/repro_fixed.out
    fail "reproduce.py FAILED on the graded tree /app/src"
fi

# 3d) the networkx being graded must literally BE the tree at /app/src: a
#     package directory planted in site-packages must never shadow it (the
#     graded tree is first on PYTHONPATH, and we refuse anything else).
if ! ( cd /tmp/run-fixed && PYTHONPATH="/app/src:$SP" python3 -S -c "import networkx as nx; assert nx.__file__.startswith('/app/src/'), nx.__file__; print(nx.__file__)" ) > /tmp/nxfile.out 2>&1; then
    cat /tmp/nxfile.out
    fail "import networkx does not resolve to /app/src (see /tmp/nxfile.out)"
fi

# 4) the fix must actually live in the graded TREE's source. Read the real
#    file at /app/src (the interpreter above has no sitecustomize, so this
#    reflects the code being graded): the tuple-label branch of generate_gml
#    must escape its label through escape(), and the buggy unescaped
#    f-string must be gone. This is what makes "fix the environment instead
#    of the tree" a non-option.
if ! python3 -S - <<'PY'
import re
src = open("networkx/readwrite/gml.py").read()
m = re.search(r"def generate_gml\(.*?(?=\ndef |\Z)", src, re.S)
assert m, "generate_gml not found in gml.py"
body = m.group(0)
tb = re.search(r'elif isinstance\(value, tuple\) and key == "label":.*?(?=\n\s+elif |\n\s+else)', body, re.S)
assert tb, "tuple-label branch not found in generate_gml"
branch = tb.group(0)
assert "escape(" in branch, "tuple-label branch does not escape the label"
assert 'f \' "({","".join(repr' not in branch, "buggy unescaped tuple-label f-string still present"
print("fix-in-tree: generate_gml tuple-label branch escapes through escape()")
PY
then
    fail "fix not present in the graded tree (see verifier log)"
fi

# 5) guard the golden seed: it is baked into the image but the root agent
#    could rewrite /opt/golden/test_gml.py. Refuse to run a golden file that
#    lost the regression's actual assertions or whose bytes drifted from the
#    fix commit (hash below was captured from an image built at the pinned
#    commits; recompute it whenever the UPSTREAM_SHA_* args change), then
#    plant it over the project's own test_gml.py and run the whole readwrite
#    test directory (the golden test + the project's own GML tests). The hash
#    literal lives in this script in the harness-owned read-only /tests
#    mount, so no agent-reachable file can change it.
echo "a986402afff7a577d5b1d3a17aa1458b73e3945a0786e7add07bde19df0b69b5  /opt/golden/test_gml.py" \
    | sha256sum -c - > /tmp/golden_hash_check.out 2>&1 \
    || { cat /tmp/golden_hash_check.out; fail "/opt/golden/test_gml.py hash mismatch (tampered?)"; }
grep -q "def test_tuple_label_quote_escape" /opt/golden/test_gml.py \
    || fail "/opt/golden/test_gml.py lost the regression test"
grep -q "&#34;" /opt/golden/test_gml.py \
    || fail "/opt/golden/test_gml.py lost its escape assertions"
grep -q "len(H) == 1" /opt/golden/test_gml.py \
    || fail "/opt/golden/test_gml.py lost its round-trip assertions"
cp /opt/golden/test_gml.py networkx/readwrite/tests/test_gml.py \
    || fail "cannot plant golden regression test"
if ! PYTHONPATH="/app/src:$SP" python3 -S -m pytest networkx/readwrite/tests/ -v -p no:cacheprovider > /tmp/pytest.out 2>&1; then
    tail -40 /tmp/pytest.out >&2
    fail "readwrite tests failed after planting regression test (see /tmp/pytest.out)"
fi
# the golden regression test must have actually run and passed (a
# neutralised or skipped run would leave no PASSED line even though pytest
# exited 0).
grep -q "test_tuple_label_quote_escape PASSED" /tmp/pytest.out || {
    tail -40 /tmp/pytest.out >&2
    fail "golden regression test did not run and pass (see /tmp/pytest.out)"
}
grep -q "test_quotes PASSED" /tmp/pytest.out \
    || fail "project's own test_quotes did not pass (see /tmp/pytest.out)"

# 6) three authored hidden cases: same tuple-label escape path, inputs the
#    upstream test does not use (3-tuple with an `edge` fragment, a `node`
#    fragment exercised through write_gml/read_gml, and a mixed-type label
#    with backslash+quote). On the unfixed parent tree every one of these
#    fails (parse error or injected extra node).
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case/check.py" "$work/check.py" || fail "hidden case $name: missing check.py"
    cp "$case/expected" "$work/expected" || fail "hidden case $name: missing expected"
    ( cd "$work" && PYTHONPATH="/app/src:$SP" python3 -S check.py > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: check.py exited $rc; stderr:" >> "$LOG"
        head -8 "$work/stderr.txt" >> "$LOG"
        tail -8 "$work/stdout.txt" >> "$LOG"
        fail "hidden case $name: check.py exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: marker mismatch; got:" >> "$LOG"
        od -c "$work/stdout.txt" | head -8 >> "$LOG"
        fail "hidden case $name: marker mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, deliverables, two-direction reproduction, golden regression test + readwrite suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0