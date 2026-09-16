#!/bin/bash
# Verifier for ropewalk-passage: an upstream-clone debugging task on
# starship/starship (issue #6861, ANSI color escape sequences counted as
# printable columns by the grapheme-width measurement the `starship explain`
# breakdown layout pads against).
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# module values that carry ANSI color sequences measure several columns wider
# than their visible text, so explain's column padding drifts. The agent must
# first write its OWN failing reproduction (a self-contained inline unit test
# named repro_ansi_width_* in the same source file as the measurement logic).
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, every
#      tracked file except src/print.rs is byte-identical to the pinned
#      commit's blob, no untracked non-ignored files, nothing in the object
#      store beyond the pinned commit) and that a change was made;
#   1. requires the agent's own write-up /app/summary.md;
#   2. extracts the agent's repro_ansi_width_* reproduction test functions;
#   3. checks the golden regression test bytes (/opt/golden/print_test.rs,
#      the project's own test_grapheme_aware_width as the fix commit extends
#      it, extracted at image build time; sha256-pinned);
#   4. checks the toolchain dispatchers (rustup/cargo symlink, rustc) against
#      pinned hashes, so no wrapper can lie about compilation;
#   5. plants the agent's OWN reproduction into the PRISTINE pre-fix tree,
#      rebuilds offline at 1 vCPU, and requires the run to FAIL there
#      (proving the reproduction is real: the bug makes it fail) - then
#      restores the agent's tree;
#   6. on the AGENT's tree, replaces test_grapheme_aware_width with the
#      golden regression test and plants three authored hidden cases (bold/
#      reset codes, interleaved multi-color codes, 256-color parameter
#      sequences), rebuilds the project's own unit-test harness offline and
#      runs the freshly built test binary DIRECTLY with the 'width' filter,
#      demanding that every width-related test pass and that each required
#      test name appears in `--list` (proving the binary that runs is the one
#      rebuilt from this tree with the planted tests) and as an explicit
#      ` ... ok` line; then restores the agent's tree exactly.
#
# The direct-binary belt matters: an adversarial agent could replace `cargo`
# with a shim that lies about compilation, or plant a prefabricated harness;
# a shim binary cannot know the three hidden test names (mounted only at
# verify time) and cannot put them in `--list`, so grepping both --list and
# the run output for every required name bounds that. A rewritten /opt/golden
# or a substituted dispatcher is caught by the pinned hashes.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

RESTORE=""  # path of a src/print.rs backup to restore on failure
fail() {
    if [ -n "$RESTORE" ] && [ -f "$RESTORE" ]; then
        cp "$RESTORE" /app/src/src/print.rs 2>/dev/null || true
    fi
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=109a6811cee1faae677a24a7d92fa8ed39397485
FIX=2c11c086b8da5ea43ae795fa0e71a621e983ebcc
export PATH=/opt/cargo/bin:$PATH

cd /app/src || fail "/app/src is missing"

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d .git ]; then
    fail "/app/src is not a git clone"
fi
if [ "$(git rev-parse HEAD 2>/dev/null)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD 2>/dev/null), expected pinned $PARENT"
fi
if [ "$(git rev-list HEAD --count 2>/dev/null)" != "1" ]; then
    fail "clone contains history beyond the pinned parent commit"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
fi
echo "ok: HEAD=$PARENT (single commit, fix commit absent from object store)"

# Blob-level scope: every tracked file except the one file the bug lives in
# must be byte-identical to the pinned commit's own blob (assume-unchanged /
# skip-worktree tricks cannot hide a dirty file), and no untracked non-ignored
# file may exist. Content is compared blob-vs-disk byte for byte, symlinks by
# readlink-vs-blob.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/print.rs) : ;;
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
    | grep -v '^ M src/print.rs$' \
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
    fail "working tree modified outside the width-measurement source surface (see $LOG)"
fi
echo "ok: only src/print.rs differs from the pinned tree"

if [ -z "$(git diff -- src/print.rs 2>/dev/null)" ]; then
    fail "no change in src/print.rs (nothing was fixed or reproduced)"
fi
echo "ok: src/print.rs was changed (a change is present)"

unreachable=$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)
if [ "$unreachable" != "0" ]; then
    fail "object store contains unreachable objects (see git fsck)"
fi
echo "ok: object store holds nothing beyond the pinned commit"

# ---------- 1. deliverable: summary ------------------------------------------
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
echo "ok: /app/summary.md present"

# ---------- 2. the agent's own reproduction ----------------------------------
python3 /tests/plant.py extract src/print.rs repro_ansi_width_ \
    > /logs/verifier/repros.json || fail "reproduction extraction failed"
python3 -c "
import json, sys
r = json.load(open('/logs/verifier/repros.json'))
names = r['names']
if not names:
    sys.exit(1)
for n in names:
    t = r['fns'][n]
    if t.count('fn ') != 1 or 'width_graphemes' not in t:
        sys.exit(2)
" || { msg="no self-contained repro_ansi_width_* reproduction test found in src/print.rs"
      [ "$?" = "2" ] && msg="reproduction test must be a single self-contained fn calling width_graphemes"
      fail "$msg"; }
echo "ok: agent reproduction test(s) present: $(python3 -c "import json;print(', '.join(json.load(open('/logs/verifier/repros.json'))['names']))")"

# ---------- 3. golden regression test integrity -------------------------------
GOLDEN_SHA=$(sha256sum /opt/golden/print_test.rs | awk '{print $1}')
EXPECTED_SHA=a9a602c762859e23735a5d0a4836ac0cbc8e25731609b97c09a486f8fc21346a
if [ "$GOLDEN_SHA" != "$EXPECTED_SHA" ]; then
    fail "golden regression test /opt/golden/print_test.rs was tampered with (sha256 $GOLDEN_SHA, expected $EXPECTED_SHA)"
fi
grep -q "fn test_grapheme_aware_width()" /opt/golden/print_test.rs \
    || fail "golden regression test does not contain the upstream test function"
grep -q "Magenta string test" /opt/golden/print_test.rs \
    || fail "golden regression test is missing the magenta-string assertion"
echo "ok: golden regression test bytes match the fix-commit extraction"

# ---------- 4. toolchain integrity --------------------------------------------
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

# ---------- 5. the reproduction must fail on the PRISTINE pre-fix tree --------
cp src/print.rs /logs/verifier/agent.print.rs
RESTORE=/logs/verifier/agent.print.rs
git show HEAD:src/print.rs > src/print.rs
python3 /tests/plant.py plant-repros src/print.rs /logs/verifier/repros.json src/print.rs \
    || fail "failed to plant the reproduction into the pristine tree"
touch src/print.rs
# Delete any pre-existing harness so the executable this verification runs can
# only have been produced by its own cargo invocation.
find target/debug -maxdepth 3 -type f \( -name 'starship' -o -name 'starship-*' \) -delete 2>/dev/null || true
TS=$(date +%s)
if ! cargo test --locked --offline --lib --no-run > /logs/verifier/build-prefix.log 2>&1; then
    tail -60 /logs/verifier/build-prefix.log >&2
    fail "the reproduction test did not compile against the pristine pre-fix tree (it must be self-contained and use only APIs present at the parent commit; see verifier.log.build-prefix)"
fi
PREBIN=""
while IFS= read -r cand; do
    case "$cand" in
        *.d) continue ;;
    esac
    PREBIN="$cand"
    break
done < <(find target/debug -maxdepth 3 -type f -newermt "@$TS" \( -name 'starship' -o -name 'starship-*' \) -print 2>/dev/null)
if [ -z "$PREBIN" ] || [ ! -x "$PREBIN" ]; then
    fail "could not locate the freshly rebuilt unit-test harness for the pristine tree"
fi
# The located harness must be a genuine ELF executable produced by the pinned
# toolchain (a shell/script fake cannot be picked even if it survived a race).
magic=$(head -c 4 "$PREBIN" 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [ "$magic" != "7f454c46" ]; then
    fail "located pristine harness $PREBIN is not an ELF executable (possible planted fake)"
fi
if [ "$(stat -c %u "$PREBIN" 2>/dev/null)" != "$(id -u)" ]; then
    fail "located pristine harness $PREBIN is not owned by the verifying user"
fi
if ! "$PREBIN" --list 2>/dev/null | grep -q "repro_ansi_width_"; then
    fail "the pristine harness does not contain the reproduction test (the planted test did not compile in)"
fi
if "$PREBIN" width > /logs/verifier/run-prefix.log 2>&1; then
    tail -30 /logs/verifier/run-prefix.log >&2
    fail "the reproduction test PASSES on the pristine pre-fix tree (a reproduction must fail before the fix; see verifier.log.run-prefix)"
fi
echo "ok: the agent's reproduction FAILS on the pristine pre-fix tree (bug reproduced)"
cp /logs/verifier/agent.print.rs src/print.rs

# ---------- 6. golden + hidden cases on the AGENT's fixed tree ----------------
python3 /tests/plant.py plant-final src/print.rs /opt/golden/print_test.rs \
    /tests/hidden/bold-reset/zz_ansi_width_bold_and_reset.rs \
    /tests/hidden/multicolor/zz_ansi_width_multicolor_mid.rs \
    /tests/hidden/colors256/zz_ansi_width_256color_suffix.rs \
    src/print.rs \
    || fail "failed to plant golden regression test and hidden cases"
touch src/print.rs
find target/debug -maxdepth 3 -type f \( -name 'starship' -o -name 'starship-*' \) -delete 2>/dev/null || true
TS=$(date +%s)
if ! cargo test --locked --offline --lib --no-run > /logs/verifier/build.log 2>&1; then
    tail -60 /logs/verifier/build.log >&2
    fail "cargo test --no-run failed after planting regression/hidden tests (see verifier.log.build)"
fi
BIN=""
while IFS= read -r cand; do
    case "$cand" in
        *.d) continue ;;
    esac
    if "$cand" --list 2>/dev/null | grep -q "zz_ansi_width_bold_and_reset"; then
        BIN="$cand"
        break
    fi
done < <(find target/debug -maxdepth 3 -type f -newermt "@$TS" \( -name 'starship' -o -name 'starship-*' \) -print 2>/dev/null)
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    fail "could not locate the freshly rebuilt unit-test harness under target/debug"
fi
magic=$(head -c 4 "$BIN" 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [ "$magic" != "7f454c46" ]; then
    fail "located harness $BIN is not an ELF executable (possible planted fake)"
fi
if [ "$(stat -c %u "$BIN" 2>/dev/null)" != "$(id -u)" ]; then
    fail "located harness $BIN is not owned by the verifying user"
fi
echo "ok: rebuilt harness $BIN (ELF, fresh, built by the pinned toolchain)"

# The binary itself must know every required test name: proves the executable
# being run is the one rebuilt from THIS tree with the planted tests (a fake
# or stale binary cannot know the hidden names).
"$BIN" --list > /logs/verifier/list.log 2>&1 || true
python3 -c "
import json
names = json.load(open('/logs/verifier/repros.json'))['names']
print('test_grapheme_aware_width')
for n in names:
    print(n)
print('zz_ansi_width_bold_and_reset')
print('zz_ansi_width_multicolor_mid')
print('zz_ansi_width_256color_suffix')
print('modules::status::tests::pipestatus_width')
print('segment::fill_seg_tests::ansi_string_width')
" > /logs/verifier/required.txt
missing=0
while IFS= read -r t; do
    if ! grep -q "${t}:" /logs/verifier/list.log; then
        echo "required test $t missing from harness --list" >> "$LOG"
        missing=1
    fi
done < /logs/verifier/required.txt
if [ "$missing" != "0" ]; then
    fail "the rebuilt harness does not contain all required tests (see verifier.log)"
fi
echo "ok: the rebuilt harness knows every required test"

# Run the harness directly with the 'width' filter: every width-related unit
# test must run and pass.
if ! "$BIN" width > /logs/verifier/run.log 2>&1; then
    tail -60 /logs/verifier/run.log >&2
    fail "width-related unit tests failed (exit non-zero); see output above"
fi
ran=0
while IFS= read -r t; do
    if ! grep -q "${t} \.\.\. ok" /logs/verifier/run.log; then
        echo "required test ${t} did not run and pass (no '${t} ... ok' line)" >> "$LOG"
        ran=1
    fi
done < /logs/verifier/required.txt
if [ "$ran" != "0" ]; then
    fail "not every required width-related test ran and passed (see verifier.log)"
fi
echo "ok: all $(wc -l < /logs/verifier/required.txt) required width-related tests ran and passed (harness exit 0)"

# ---------- 7. restore the tree to exactly what the agent left ---------------
cp /logs/verifier/agent.print.rs src/print.rs
RESTORE=""

echo 1 > /logs/verifier/reward.txt
exit 0