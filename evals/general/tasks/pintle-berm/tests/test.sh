#!/bin/bash
# Verifier for pintle-berm: a debugging task inside a pinned clone of
# rust-lang/regex at the parent commit (release 1.9.2) where the reverse
# inner literal optimization can report a real-but-not-leftmost match when a
# pattern's first alternative is optional (upstream issue #1060).
#
# The agent must (a) author its own failing regression case(s) in
# /app/src/testdata/regression.toml encoding the CORRECT expected behaviour
# (leftmost match, exact byte offsets and captures), (b) fix the source so
# the harness passes, and (c) write /app/report.md naming its new case.
#
# The verifier:
#   0. re-checks the trust anchors pinned at image build time (cargo, rustc,
#      git and the golden regression test sha256 sums) so a substituted
#      toolchain or test can never earn reward 1;
#   1. checks provenance: /app/src and /opt/pristine are both the pinned
#      parent commit, the upstream fix commit is unreachable from either
#      clone, every tracked file except regex-automata/src/meta/limited.rs
#      and testdata/regression.toml is byte-identical to the pinned commit
#      (an actual-blob content check, so assume-unchanged tricks cannot
#      hide a dirty file), no untracked non-ignored files exist, and the two
#      allowed files actually differ from the pinned commit;
#   2. requires /app/report.md and that it names one of the agent's new
#      regression cases;
#   3. replays the agent's own regression file against the PRISTINE pre-fix
#      tree (/opt/pristine, same parent commit, read-only since build time):
#      the harness must FAIL blaming one of the agent's new case names,
#      proving the reproduction genuinely captures the bug; the pristine
#      tree is then restored and re-verified clean;
#   4. rebuilds /app/src from the agent's tree (integration binaries
#      deleted first so nothing planted under git-ignored target/ survives)
#      and runs in sequence:
#        - the agent's own regression file            -> must pass,
#        - the upstream golden regression test        -> must pass,
#        - the agent's reproduction ONCE MORE against the pristine tree
#          after the tree was rebuilt (belt: the code that passes the
#          golden test must also satisfy the agent's own repro),
#        - the project's own full integration suite with the vanilla
#          test data (all 64 tests)                   -> must pass,
#        - the changed crate's deep engine-level suite (53 tests),
#        - three authored hidden optional-prefix cases -> must pass.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

PARENT=bbf0b38df618734b92d7b92acc8a8bf31b6d0046
FIX=73f7889021542ea80937b3adacefa5825eaa97fe
export PATH=/opt/cargo/bin:$PATH CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup
GIT=/usr/bin/git
SRC=/app/src
PRISTINE=/opt/pristine
GOLDEN=/opt/golden-regression.toml

fail() {
  echo "FAIL: $1" >&2
  echo 0 > /logs/verifier/reward.txt
  exit 0
}

echo "== 0. trust anchors =="
if ! ( cd / && sha256sum -c /opt/pins/anchors.sha256 > /dev/null 2>&1 ); then
  fail "toolchain or golden integrity check failed (substituted binary/test)"
fi
echo "ok: cargo, rustc, git and golden test match the build-time pins"

echo "== 1. provenance =="
[ "$("$GIT" -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$PARENT" ] \
  || fail "/app/src HEAD is '$("$GIT" -C "$SRC" rev-parse HEAD 2>/dev/null)', expected $PARENT"
echo "ok: /app/src HEAD is $PARENT"

[ "$("$GIT" -C "$PRISTINE" rev-parse HEAD 2>/dev/null)" = "$PARENT" ] \
  || fail "/opt/pristine HEAD is not the pinned parent commit"
echo "ok: /opt/pristine HEAD is $PARENT"

if "$GIT" -C "$SRC" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from /app/src"
fi
if "$GIT" -C "$PRISTINE" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from /opt/pristine"
fi
echo "ok: the upstream fix commit is unreachable from both clones"

# Blob-level scope check: every tracked file except the two allowed paths
# must be byte-identical to its parent blob.
ok=1
: > /tmp/scope.log
while IFS= read -r -d '' f; do
  case "$f" in
    regex-automata/src/meta/limited.rs|testdata/regression.toml) continue ;;
  esac
  want=$("$GIT" -C "$SRC" rev-parse "$PARENT:$f" 2>/dev/null || true)
  if [ -z "$want" ]; then
    echo "tracked file not in parent tree: $f" >> /tmp/scope.log; ok=0; continue
  fi
  if [ -L "/app/src/$f" ]; then
    have=$(printf '%s' "$(readlink "/app/src/$f")" | "$GIT" hash-object --stdin 2>/dev/null || true)
  else
    have=$("$GIT" hash-object "/app/src/$f" 2>/dev/null || true)
  fi
  if [ -z "$have" ] || [ "$have" != "$want" ]; then
    echo "out-of-scope modified/deleted tracked file: $f" >> /tmp/scope.log; ok=0
  fi
done < <("$GIT" -C "$SRC" ls-files -z)
while IFS= read -r -d '' f; do
  echo "untracked non-ignored file: $f" >> /tmp/scope.log; ok=0
done < <("$GIT" -C "$SRC" ls-files --others -z --exclude-standard)

src_blob=$("$GIT" -C "$SRC" hash-object "$SRC/regex-automata/src/meta/limited.rs" 2>/dev/null || true)
parent_src=$("$GIT" -C "$SRC" rev-parse "$PARENT:regex-automata/src/meta/limited.rs" 2>/dev/null || true)
if [ -z "$src_blob" ] || [ "$src_blob" = "$parent_src" ]; then
  echo "the buggy source file is unchanged (no fix implemented)" >> /tmp/scope.log; ok=0
fi
testdata_blob=$("$GIT" -C "$SRC" hash-object "$SRC/testdata/regression.toml" 2>/dev/null || true)
parent_testdata=$("$GIT" -C "$SRC" rev-parse "$PARENT:testdata/regression.toml" 2>/dev/null || true)
if [ -z "$testdata_blob" ] || [ "$testdata_blob" = "$parent_testdata" ]; then
  echo "testdata/regression.toml is unchanged (no reproduction authored)" >> /tmp/scope.log; ok=0
fi
if [ "$ok" != 1 ]; then
  cat /tmp/scope.log >&2
  fail "working tree out of scope (see above)"
fi
echo "ok: the only differences from the pinned commit are testdata/regression.toml and the source fix"

echo "== 2. agent reproduction cases =="
python3 - "$SRC/testdata/regression.toml" "$PARENT" <<'PYEOF' || fail "could not parse the agent's testdata/regression.toml"
import subprocess, sys, tomllib

agent_path, parent_sha = sys.argv[1], sys.argv[2]
with open(agent_path, "rb") as f:
    agent_tests = tomllib.load(f).get("test", [])
agent_names = {t.get("name") for t in agent_tests if isinstance(t, dict) and t.get("name")}
missing = [t for t in agent_tests if not isinstance(t, dict) or not t.get("name")]
if missing:
    print("FAIL: entries without a name:", missing); sys.exit(1)

parent_raw = subprocess.run(
    ["/usr/bin/git", "-C", "/app/src", "show", f"{parent_sha}:testdata/regression.toml"],
    capture_output=True, check=True).stdout
import tomllib as tl
parent_names = set(t.get("name") for t in tl.loads(parent_raw.decode()).get("test", []))
if not parent_names <= agent_names:
    print("FAIL: parent regression cases missing from the agent file:", sorted(parent_names - agent_names))
    sys.exit(1)
new_names = sorted(agent_names - parent_names)
if not new_names:
    print("FAIL: no new regression case authored (file identical to parent corpus)")
    sys.exit(1)
with open("/tmp/agent-new-names", "w") as f:
    f.write("\n".join(new_names))
print("ok: agent authored new regression case(s):", ", ".join(new_names))
PYEOF

echo "== 3. /app/report.md =="
[ -s /app/report.md ] || fail "/app/report.md is missing or empty"
size=$(wc -c < /app/report.md)
[ "$size" -ge 100 ] || fail "/app/report.md is suspiciously short ($size bytes)"
# The agent's authorship must not be satisfiable by copying the upstream
# golden regression file: an agent-authored case must have a name that is NOT
# one of the fix-era names, and the report must name such a case.
# (The golden file is root-only since the image build, so the names below are
# not readable by the agent; this check is belt-and-braces.)
: > /tmp/golden-names
golden_names=$(python3 - "$GOLDEN" <<'PYEOF'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    names = [t.get("name") for t in tomllib.load(f).get("test", []) \
             if isinstance(t, dict) and t.get("name")]
print("\n".join(names))
PYEOF
)
own=""
for n in $(cat /tmp/agent-new-names); do
  if ! printf '%s\n' "$golden_names" | grep -qxF "$n"; then own="$own $n"; fi
done
[ -n "$own" ] || fail "every new regression case matches an upstream golden case name; author your own reproducer"
hit=""
for n in $own; do
  grep -qF "$n" /app/report.md && hit="$hit $n"
done
[ -n "$hit" ] || fail "/app/report.md does not name an agent-authored regression case"
echo "ok: /app/report.md ($size bytes) names author-owned case(s):$hit"

echo "== 4. agency: replay the agent's reproduction against the pre-fix tree =="
# /opt/pristine is the same parent commit, left read-only since image build;
# the verifier (uid 0) restores write access for the rebuild and re-locks it.
if [ "$(id -u)" = 0 ]; then chmod -R u+rwX "$PRISTINE"; fi
"$GIT" -C "$PRISTINE" status --porcelain | grep -q . \
  && fail "/opt/pristine has uncommitted changes (tampered)"
pristine_src=$("$GIT" -C "$PRISTINE" hash-object "$PRISTINE/regex-automata/src/meta/limited.rs")
[ "$pristine_src" = "$parent_src" ] || fail "/opt/pristine source differs from the pinned parent blob"
cp "$SRC/testdata/regression.toml" "$PRISTINE/testdata/regression.toml"
rm -f "$PRISTINE"/target/debug/deps/integration-* 2>/dev/null
if [ "$(id -u)" = 0 ]; then chmod -R u+rwX "$PRISTINE"; fi
if ! ( cd "$PRISTINE" && cargo test --test integration --no-run > /tmp/pristine-build.log 2>&1 ); then
  fail "pristine pre-fix tree failed to rebuild with the agent's test data"
fi
( cd "$PRISTINE" && cargo test --test integration -- suite_string::default > /tmp/pristine-run.log 2>&1 )
rc=$?
hits=""
for n in $(cat /tmp/agent-new-names); do
  grep -aq "regression/$n/" /tmp/pristine-run.log && hits="$hits $n"
done
if [ "$rc" = 0 ] || [ -z "$hits" ]; then
  tail -30 /tmp/pristine-run.log >&2 2>/dev/null
  fail "the agent's reproduction did not FAIL against the pre-fix tree (rc=$rc); new cases: $(cat /tmp/agent-new-names | tr '\n' ' ')"
fi
echo "ok: the agent's reproduction genuinely fails the pre-fix tree, blaming: $hits"
"$GIT" -C "$PRISTINE" show "$PARENT:testdata/regression.toml" > "$PRISTINE/testdata/regression.toml"
"$GIT" -C "$PRISTINE" status --porcelain | grep -q . && fail "/opt/pristine not restored"
if [ "$(id -u)" = 0 ]; then chmod -R a-w "$PRISTINE" && find "$PRISTINE" -type d -exec chmod a+rx {} \;; fi
echo "ok: /opt/pristine restored and re-locked"

echo "== 5. rebuild the agent's tree and run every corpus =="
cp "$SRC/testdata/regression.toml" /tmp/agent-testdata.toml
rm -f "$SRC"/target/debug/deps/integration-* 2>/dev/null
if ! ( cd "$SRC" && cargo test --test integration --no-run > /tmp/agent-build.log 2>&1 ); then
  tail -40 /tmp/agent-build.log >&2
  fail "the repaired tree does not build"
fi
echo "ok: the repaired tree builds"

# 5.1 the agent's own reproduction must pass in the repaired tree
cp /tmp/agent-testdata.toml "$SRC/testdata/regression.toml"
if ! ( cd "$SRC" && cargo test --test integration -- suite_string::default > /tmp/ra.log 2>&1 ); then
  tail -30 /tmp/ra.log >&2
  fail "the agent's own regression file fails in the repaired tree"
fi
echo "ok: agent's own regression file passes in the repaired tree"

# 5.2 the upstream golden regression test (extracted from the fix commit at
#     image build time, sha256-pinned) must pass in the repaired tree
cp "$GOLDEN" "$SRC/testdata/regression.toml"
grep -q 'name = "reverse-inner-plus-shorter-than-expected"' "$SRC/testdata/regression.toml" \
  || fail "golden test file unexpectedly altered"
if ! ( cd "$SRC" && cargo test --test integration -- suite_string::default > /tmp/rb.log 2>&1 ); then
  tail -30 /tmp/rb.log >&2
  fail "the upstream golden regression test did not pass in the repaired tree"
fi
grep -q "1 passed" /tmp/rb.log || fail "golden run did not report the suite passing"
echo "ok: upstream golden regression test passes"

# 5.3 the agent's reproduction ONCE MORE, after the rebuild (belt)
cp /tmp/agent-testdata.toml "$SRC/testdata/regression.toml"
if ! ( cd "$SRC" && cargo test --test integration -- suite_string::default > /tmp/ra2.log 2>&1 ); then
  tail -30 /tmp/ra2.log >&2
  fail "agent's reproduction fails after the rebuild"
fi
echo "ok: agent's reproduction still passes"

# 5.4 the project's own full integration suite with the vanilla test data
"$GIT" -C "$SRC" show "$PARENT:testdata/regression.toml" > "$SRC/testdata/regression.toml"
if ! ( cd "$SRC" && cargo test --test integration > /tmp/rc.log 2>&1 ); then
  tail -30 /tmp/rc.log >&2
  fail "the project's full integration suite failed"
fi
grep -q "64 passed" /tmp/rc.log || { tail -20 /tmp/rc.log >&2; fail "full integration suite did not report 64 passed"; }
echo "ok: project's full integration suite green (64 tests)"

# 5.5 the changed crate's deep engine-level suite
if ! ( cd "$SRC" && cargo test --manifest-path regex-automata/Cargo.toml --test integration > /tmp/rd.log 2>&1 ); then
  tail -30 /tmp/rd.log >&2
  fail "the regex-automata deep engine-level suite failed"
fi
grep -q "53 passed" /tmp/rd.log || { tail -20 /tmp/rd.log >&2; fail "deep suite did not report 53 passed"; }
echo "ok: regex-automata deep engine-level suite green (53 tests)"

echo "== 6. authored hidden cases =="
n_hidden=0
: > /tmp/hidden-planted.toml
"$GIT" -C "$SRC" show "$PARENT:testdata/regression.toml" > /tmp/hidden-planted.toml
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  cat "$case/entries.toml" >> /tmp/hidden-planted.toml || fail "hidden case $(basename "$case") missing entries.toml"
done
[ "$n_hidden" -ge 2 ] || fail "fewer than two hidden cases were exercised"
cp /tmp/hidden-planted.toml "$SRC/testdata/regression.toml"
if ! ( cd "$SRC" && cargo test --test integration -- suite_string::default > /tmp/rh.log 2>&1 ); then
  tail -30 /tmp/rh.log >&2
  fail "authored hidden cases failed ($n_hidden case dirs)"
fi
echo "ok: $n_hidden authored hidden case dirs pass ($(grep -c '^name' /tmp/hidden-planted.toml) entries)"

echo "PASS: provenance, report, genuine reproduction, golden test, full suites and hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0