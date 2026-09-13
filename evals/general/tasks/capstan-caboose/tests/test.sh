#!/bin/bash
# Verifier for capstan-caboose: an upstream-clone debugging task on
# starship/starship (issue #7426, maven module fires on any .mvn directory).
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the maven prompt module activates in any directory that merely contains an
# .mvn folder (e.g. only .mvn/maven.config) instead of only for real Maven
# projects (pom.xml or .mvn/wrapper/maven-wrapper.properties). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, every
#      tracked file except the two maven source files is byte-identical to
#      the pinned commit's blob, no untracked non-ignored files, nothing in
#      the object store beyond the pinned commit) and that a change was made;
#   1. requires the agent's own write-up /app/summary.md;
#   2. plants the project's OWN regression test for this bug (the single
#      test function the fix commit added inline in src/modules/maven.rs,
#      extracted at image build time into /opt/golden; sha256-pinned against
#      the exact bytes) plus three authored hidden test functions (pom.xml
#      only, wrapper-properties only, .mvn dir with a non-wrapper file);
#   3. rebuilds the project's own unit-test harness offline (cargo test
#      --no-run) and runs the freshly built test binary DIRECTLY with the
#      maven filter, demanding that all 9 maven-module tests pass AND that
#      each required test name appears in `--list` (proving the binary that
#      runs is the one built from the tree with the planted tests) and as an
#      explicit `... ok` line.
#
# The direct-binary belt matters: /opt/cargo/bin is world-writable so an
# adversarial agent could replace `cargo` with a shim that lies about
# compilation and prints fake results; a shim binary cannot know the three
# hidden test names (they are mounted only at verify time) and cannot put them
# in `--list`, so grepping both --list and the run output for every required
# name bounds that. A rewritten /opt/golden is caught by the pinned sha256.
#
# Reward is binary and written on every exit path (trap below).

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

PARENT=d0e246802c85d5aa956f536f9ab7ead282dbab7a
FIX=d455255e7bc5ae5e96ac5a3e2610458a9f213b49
export PATH=/opt/cargo/bin:$PATH

cd /app/src || fail "/app/src is missing"

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d .git ]; then
    fail "/app/src is not a git clone"
fi
if [ "$(git rev-parse HEAD 2>/dev/null)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if [ "$(git rev-list HEAD --count 2>/dev/null)" != "1" ]; then
    fail "clone contains history beyond the pinned parent commit"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
fi
echo "ok: HEAD=$PARENT (single commit, fix commit absent from object store)"

# Blob-level scope: every tracked file except the two files the bug lives in
# must be byte-identical to the pinned commit's own blob (assume-unchanged /
# skip-worktree tricks cannot hide a dirty file), and no untracked non-ignored
# file may exist. A plain `git hash-object` would follow symlinks (the tree
# contains symlinks such as docs/guide/README.md), so content is compared
# blob-vs-disk byte for byte, and symlinks by readlink-vs-blob.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/modules/maven.rs|src/configs/maven.rs) : ;;
        *)
            if [ -L "$f" ]; then
                want=$(git cat-file blob "$PARENT:$f" 2>/dev/null | cat)
                have=$(readlink "$f")
                if [ "$have" != "$want" ]; then
                    echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"
                    ok=0
                fi
            else
                if ! git cat-file blob "$PARENT:$f" 2>/dev/null | cmp -s - "$f"; then
                    echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"
                    ok=0
                fi
            fi
            ;;
    esac
done < <(git ls-files -z)
# Belt: any tracked-path status entry other than a modified allowed file, and
# any untracked non-ignored file, fails (deletions, renames, mode changes).
porcelain=$(git status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" \
    | grep -v '^ M src/modules/maven.rs$' \
    | grep -v '^ M src/configs/maven.rs$' \
    | grep -v '^?? ' \
    | grep -v '^$' || true)
if [ -n "$bad" ]; then
    echo "unexpected status entries (deletions/renames/mode changes):" >> "$LOG"
    printf '%s\n' "$bad" | head -10 >> "$LOG"
    ok=0
fi
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"
    ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    fail "working tree modified outside the maven source surface (see $LOG)"
fi
echo "ok: only the maven source surface differs from the pinned tree"
if [ -z "$(git diff -- src/modules/maven.rs src/configs/maven.rs 2>/dev/null)" ]; then
    fail "no change in the maven module sources (nothing was fixed)"
fi
echo "ok: the maven source surface was changed (a fix is present)"

unreachable=$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)
if [ "$unreachable" != "0" ]; then
    fail "object store contains unreachable objects (see git fsck)"
fi
echo "ok: object store holds nothing beyond the pinned commit"

# ---------- 1. deliverable ----------------------------------------------------
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
echo "ok: /app/summary.md present"

# ---------- 2. golden integrity -----------------------------------------------
GOLDEN_SHA=$(sha256sum /opt/golden/maven_test.rs | awk '{print $1}')
EXPECTED_SHA=319d1b761f5878344f6fd00ad61fc2140c51263429909d4b709844082a0fb200
if [ "$GOLDEN_SHA" != "$EXPECTED_SHA" ]; then
    fail "golden regression test /opt/golden/maven_test.rs was tampered with (sha256 $GOLDEN_SHA, expected $EXPECTED_SHA)"
fi
grep -q "fn folder_with_maven_config_does_not_trigger_module(" /opt/golden/maven_test.rs \
    || fail "golden regression test does not contain the upstream test function"
echo "ok: golden regression test bytes match the fix-commit extraction"

# ---------- 2.5 toolchain integrity -------------------------------------------
# /opt/cargo is world-writable in the shipped image (cargo writes bookkeeping
# under CARGO_HOME as uid 1000), so a substituted `cargo`/`rustup` dispatcher or
# a re-pointed symlink is the classic wrapper attack, and the direct-binary belt
# below cannot stop a shim that fabricates a harness AT VERIFY TIME (it can read
# the just-uploaded /tests and /opt/golden to learn every hidden test name). The
# dispatcher is therefore hash-pinned: the pinned binaries are per-version
# immutable toolchain artifacts, so a swapped or shimmed dispatcher cannot match
# the pinned digests and the only way `cargo test` runs is with the genuine
# toolchain against the tree as it exists now.
cargo_link=$(readlink /opt/cargo/bin/cargo 2>/dev/null || true)
if [ "$cargo_link" != "rustup" ]; then
    fail "/opt/cargo/bin/cargo is not the rustup dispatcher symlink (got '$cargo_link')"
fi
RUSTUP_SHA=$(sha256sum /opt/cargo/bin/rustup | awk '{print $1}')
if [ "$RUSTUP_SHA" != "dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71" ]; then
    fail "rustup/cargo dispatcher was substituted (sha256 $RUSTUP_SHA)"
fi
RUSTC_PATH=$(find /opt/rustup/toolchains -path '*/bin/rustc' -type f 2>/dev/null | head -1)
case "$RUSTC_PATH" in
    /opt/rustup/toolchains/*/bin/rustc) : ;;
    *) fail "toolchain rustc not found under /opt/rustup/toolchains (got '$RUSTC_PATH')" ;;
esac
RUSTC_SHA=$(sha256sum "$RUSTC_PATH" | awk '{print $1}')
if [ "$RUSTC_SHA" != "859254978c0a0402c32f949f6de0d99aee73be8d15f45aac00ae1448aac51e74" ]; then
    fail "toolchain rustc was substituted (sha256 $RUSTC_SHA)"
fi
echo "ok: cargo (rustup proxy, sha256 ${RUSTUP_SHA:0:12}...) and rustc (sha256 ${RUSTC_SHA:0:12}...) are the pinned toolchain binaries"

# ---------- 3. plant the regression test and the hidden cases -----------------
cp src/modules/maven.rs /logs/verifier/maven.before
plant() {  # plant NAME FILE
    name="$1"; file="$2"
    if ! grep -q "fn $name(" src/modules/maven.rs; then
        sed -i "/^mod tests {\$/r $file" src/modules/maven.rs
    fi
}
plant folder_with_maven_config_does_not_trigger_module /opt/golden/maven_test.rs
plant pom_xml_alone_still_triggers_maven_module /tests/hidden/pom-xml-only/zz_pom_xml_triggers.rs
plant wrapper_properties_alone_triggers_maven_module /tests/hidden/wrapper-properties/zz_wrapper_props_triggers.rs
plant mvn_dir_without_pom_or_wrapper_does_not_trigger_module /tests/hidden/dotdir-no-trigger/zz_mvn_settings_xml_ignored.rs
for name in \
    folder_with_maven_config_does_not_trigger_module \
    pom_xml_alone_still_triggers_maven_module \
    wrapper_properties_alone_triggers_maven_module \
    mvn_dir_without_pom_or_wrapper_does_not_trigger_module; do
    grep -q "fn $name(" src/modules/maven.rs || fail "failed to plant test function $name"
done
echo "ok: upstream regression test and 3 hidden cases planted into mod tests"

REQUIRED_TESTS="folder_without_maven_files
folder_with_maven_wrapper_properties
maven_wrapper_recursive
test_format_wrapper_properties
test_format_wrapper_properties_unstable_versions
folder_with_maven_config_does_not_trigger_module
pom_xml_alone_still_triggers_maven_module
wrapper_properties_alone_triggers_maven_module
mvn_dir_without_pom_or_wrapper_does_not_trigger_module"

# Force cargo to recompile the crate from the tree as it exists NOW: if the
# tree already matches the last compiled content (e.g. an agent or the oracle
# ran cargo on an identical state, or a restore raced the previous build),
# cargo would legitimately report up-to-date and no fresh harness would be
# produced. Touching the changed source makes the rebuild deterministic, so
# the harness that runs next is guaranteed to reflect this tree. The rebuild
# is incremental (one source file + link, tens of seconds at 1 vCPU).
touch src/modules/maven.rs

# ---------- 4. rebuild the project's own unit-test harness, offline ------------
# `cargo test --no-run` recompiles only the crate touched above (incremental,
# tens of seconds at 1 vCPU) and refreshes the harness executables. First every
# pre-existing candidate under target/debug is deleted, so the executable the
# finder ends up running can only have been produced by THIS verification's own
# cargo invocation: a planted fake harness is gone whatever mtime it carries
# (future-dated ones would otherwise survive any -newermt window).
find target/debug -maxdepth 3 -type f \( -name 'starship' -o -name 'starship-*' \) -delete 2>/dev/null || true
TS=$(date +%s)
if ! cargo test --locked --offline --no-run > "$LOG.build" 2>&1; then
    tail -60 "$LOG.build" >&2
    cp /logs/verifier/maven.before src/modules/maven.rs
    fail "cargo test --no-run failed after planting regression/hidden tests (see verifier.log.build)"
fi

# Locate the freshly built unit-test harness: cargo rebuilds one or more
# `target/debug/deps/starship-<hash>` harnesses after the planted tests; pick
# the executable written during this verification that actually LISTS the
# planted golden test (the lib harness `unittests src/lib.rs` holds the module
# unit tests; the bin harness and other stale harnesses do not).
BIN=""
while IFS= read -r cand; do
    case "$cand" in
        *.d) continue ;;
    esac
    if "$cand" --list 2>/dev/null | grep -q "folder_with_maven_config_does_not_trigger_module"; then
        BIN="$cand"
        break
    fi
done < <(find target/debug -maxdepth 3 -type f -newermt "@$TS" \( -name 'starship' -o -name 'starship-*' \) -print 2>/dev/null)
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    cp /logs/verifier/maven.before src/modules/maven.rs
    fail "could not locate the freshly rebuilt unit-test harness under target/debug"
fi
# The located harness must be a genuine ELF executable produced by the pinned
# toolchain (a shell/script fake cannot be picked even if it survived a race),
# owned by the user verifying, and touched within this verification window.
magic=$(head -c 4 "$BIN" 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [ "$magic" != "7f454c46" ]; then
    cp /logs/verifier/maven.before src/modules/maven.rs
    fail "located harness $BIN is not an ELF executable (possible planted fake)"
fi
if [ "$(stat -c %u "$BIN" 2>/dev/null)" != "$(id -u)" ]; then
    cp /logs/verifier/maven.before src/modules/maven.rs
    fail "located harness $BIN is not owned by the verifying user"
fi
echo "ok: rebuilt harness $BIN (ELF, fresh, built by the pinned toolchain)"

# The binary itself must know every required test name: proves the executable
# being run is the one rebuilt from THIS tree with the planted tests (a fake
# or stale binary cannot know the hidden names).
"$BIN" --list > /tmp/maven.list 2>&1 || true
missing=0
while IFS= read -r t; do
    if ! grep -q "::${t}$\|::${t} \.\.\|::${t}:" /tmp/maven.list; then
        echo "required test $t missing from harness --list" >> "$LOG"
        missing=1
    fi
done <<EOF
$REQUIRED_TESTS
EOF
if [ "$missing" != "0" ]; then
    cp /logs/verifier/maven.before src/modules/maven.rs
    fail "the rebuilt harness does not contain all required tests (see verifier.log)"
fi
echo "ok: the rebuilt harness knows all 9 required tests"

# ---------- 5. run the harness directly with the maven filter -----------------
if ! "$BIN" maven > /tmp/maven.run 2>&1; then
    tail -60 /tmp/maven.run >&2
    cp /logs/verifier/maven.before src/modules/maven.rs
    fail "maven-module tests failed (exit non-zero); see output above"
fi
ran=0
while IFS= read -r t; do
    if ! grep -q "::${t} \.\.\. ok" /tmp/maven.run; then
        echo "required test ${t} did not run and pass (no '::${t} ... ok' line)" >> "$LOG"
        ran=1
    fi
done <<EOF
$REQUIRED_TESTS
EOF
if [ "$ran" != "0" ]; then
    cp /logs/verifier/maven.before src/modules/maven.rs
    fail "not every required maven-module test ran and passed (see verifier.log)"
fi
echo "ok: all 9 required maven-module tests ran and passed (harness exit 0)"

# ---------- 6. restore the tree to exactly what the agent left -----------------
cp /logs/verifier/maven.before src/modules/maven.rs

echo 1 > /logs/verifier/reward.txt
exit 0