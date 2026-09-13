#!/bin/bash
# Verifier for capstan-quay: a real-upstream debugging task on
# gohugoio/hugo.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# a content page consisting ONLY of front matter (no body) leaks the raw
# front matter text (the delimiters and the keys) into output that prints
# {{ .RawContent }}, because the body offset is only recorded when the
# parser has not reached end-of-input. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, exactly
#      one commit object, no tracked file deleted, the only modified tracked
#      files are non-test sources under hugolib/ with at least one such
#      modification present, and the test-harness helper
#      hugolib/integrationtest_builder.go is untouched);
#   1. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/
#      (the fix-commit version of hugolib/page_test.go, TestPageRawContent) --
#      this test FAILS on the pristine parent tree and must PASS on a fixed
#      tree;
#   2. restores the tree's own page_test.go and runs two authored hidden
#      cases plus the reproduction probe from /app, which exercise the same
#      code path with inputs the upstream regression test does not use (TOML
#      front matter in a section directory; a long YAML block in a dated
#      path);
#   3. runs a slice of the project's own existing hugolib tests around page
#      parsing, front matter and content, proving the fix broke nothing
#      else.
#
# Reward is binary and written on every exit path.
#
# --- verifier hardening (added in review) -----------------------------------
# The verifier runs inside the agent's own container after the agent stops
# (harbor "shared" mode). Only /tests is re-uploaded from the host at verify
# time; /opt/golden/, /app/probe_test.go, and the toolchain binaries are
# baked into the image, so a root agent can swap any of them. Three bypasses
# were demonstrated against the unhardened verifier:
#   1. replacing /usr/local/go/bin/go with a script that prints the expected
#      "--- PASS: <test>" lines and exits 0, earning reward 1 with the bug
#      fully intact;
#   2. neutering the AssertFileContent helper in hugolib/integrationtest_
#      builder.go and hiding the change with `git update-index
#      --assume-unchanged`, also earning reward 1 with the bug intact;
#   3. pre-writing /logs/verifier/reward.txt so that an abnormal exit of the
#      old trap (which wrote 0 only when the file was absent) left a forged 1.
# Defences, all evaluated against the real image:
#   - the reward file is removed at start and unconditionally rewritten in an
#     EXIT trap (no path can leave a stale/forged value);
#   - sha256 of the go binary, the git binary, the golden regression test and
#     the probe are bound to constants recorded at authoring time; any of
#     them swapped, replaced or deleted fails the task;
#   - assume-unchanged / skip-worktree index entries are rejected, so a
#     modified tracked file cannot be hidden from `git status --porcelain'.
#
# Re-record the constants (sha256sum on each path inside the built image)
# only if the image's toolchain or harness files genuinely change; the golden
# SHA derives from upstream commit 3a8aad6b190bb3d7cecc8ec6bc8379a01ec547cb
# and the probe from the authored environment/files/probe_test.go.

trap 'printf "%s\n" "${reward:-0}" > /logs/verifier/reward.txt' EXIT
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt
reward=1

SRC=/app/src
PARENT_SHA=a7b93e6564e6a4a7a3043b431e255ba716940408
FIX_SHA=3a8aad6b190bb3d7cecc8ec6bc8379a01ec547cb

export PATH=/usr/local/go/bin:$PATH
export GOPATH=/opt/gopath GOCACHE=/opt/gocache
export GOPROXY=https://proxy.golang.org GO111MODULE=on
GO=/usr/local/go/bin/go
GIT=/usr/bin/git

# sha256 as recorded from the built capstan-quay image at authoring time.
INTEGRITY_SHA_GO=30969f97169d7f43fe6a085873d75613adc21e30818a8c61d95bd27275df4624
INTEGRITY_SHA_GIT=2a8c18fbf43da9f692d75474c72bea9dfd796c260b0f3dfe456376abc3bbd668
INTEGRITY_SHA_GOLDEN=77b5c349780e30a942537c2ebdaa5475e547ff660aba49e27de1721e33aa3273
INTEGRITY_SHA_PROBE=4ed604e14f1745b2afe031d0e57feff79d8f5046b8737f77c011c817dfd8992f

run_go () {  # run_go LABEL OUT TESTFILTER [EXPECTED_TEST ...]
  label="$1"; out="$2"; filter="$3"; shift 3
  if ( cd "$SRC" && "$GO" test -vet=off ./hugolib -run "$filter" -v > "$out" 2>&1 ); then
    for want in "$@"; do
      if ! grep -Fq -- "--- PASS: $want " "$out"; then
        echo "FAIL: $label — test '$want' did not PASS (filter matched nothing?)" >&2
        tail -20 "$out" | sed 's/^/    /' >&2
        reward=0
        return 1
      fi
    done
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0a. toolchain and harness integrity ----------------------------------
# The go and git binaries, the golden regression test and the probe are the
# four byte strings the rest of this verifier trusts. The agent must not be
# able to swap any of them, so each is bound to its recorded sha256.
echo "== toolchain and harness integrity =="
check_sha () {  # check_sha LABEL EXPECTED FILE
  local label="$1" expected="$2" file="$3"
  if [ ! -f "$file" ]; then
    echo "FAIL: integrity/$label: $file is missing (toolchain or harness was replaced or deleted)" >&2
    return 1
  fi
  local actual
  actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: integrity/$label: $file does not match the recorded bytes (was it replaced?)" >&2
    echo "  expected sha256: $expected" >&2
    echo "  actual   sha256: ${actual:-<unreadable>}" >&2
    return 1
  fi
  echo "ok: integrity/$label: matches the recorded bytes"
  return 0
}
check_sha go     "$INTEGRITY_SHA_GO"     "$GO"                    || reward=0
check_sha git    "$INTEGRITY_SHA_GIT"    "$GIT"                   || reward=0
check_sha golden "$INTEGRITY_SHA_GOLDEN" "/opt/golden/page_test.go" || reward=0
check_sha probe  "$INTEGRITY_SHA_PROBE"  "/app/probe_test.go"     || reward=0

# ---------- 0b. tree provenance -------------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$("$GIT" -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if "$GIT" -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
else
  echo "ok: fix commit not present in the working clone"
fi

ncommits=$("$GIT" -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone contains $ncommits commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  reward=0
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

# Assume-unchanged or skip-worktree index entries let the agent hide a
# modified tracked file (e.g. the test harness) from `git status --porcelain'.
# Flag them explicitly: `git ls-files -v` prints 'h.. ' for assume-unchanged
# and 'S.. ' for skip-worktree entries.
flagged=$("$GIT" -C "$SRC" ls-files -v 2>/dev/null | awk '
  NF >= 2 && $1 ~ /^[hS]/ { print }
')
if [ -n "$flagged" ]; then
  echo "FAIL: tracked files carry assume-unchanged/skip-worktree index flags (changes would be hidden from status):" >&2
  echo "$flagged" | sed 's/^/    | /' >&2
  reward=0
else
  echo "ok: no assume-unchanged / skip-worktree flags in the index"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  rest="${line#?? }"
  case "$line" in
    " M hugolib/"*)
      case "$rest" in
        *_test.go) echo "FAIL: a tracked project test file was modified: $line" >&2; bad_tree=1 ;;
        hugolib/integrationtest_builder.go) echo "FAIL: the test harness helper hugolib/integrationtest_builder.go was modified: $line" >&2; bad_tree=1 ;;
        *) saw_mod=1 ;;
      esac
      ;;
    " M "*)
      echo "FAIL: a tracked file outside hugolib/ was modified: $line" >&2; bad_tree=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*)
      # untracked files are allowed (the agent may add its own tests)
      : ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$("$GIT" -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no disallowed working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: no non-test source file under hugolib/ was modified (the deliverable /app/src is unchanged; no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one non-test source file under hugolib/ is modified"
fi

# ---------- 1. golden: the upstream regression test -----------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s /opt/golden/page_test.go ]; then
  echo "FAIL: golden file missing from the image" >&2; reward=0
else
  check_sha golden "$INTEGRITY_SHA_GOLDEN" "/opt/golden/page_test.go" || reward=0
  cp /opt/golden/page_test.go "$SRC/hugolib/page_test.go"
  run_go "golden TestPageRawContent" /tmp/golden.out TestPageRawContent TestPageRawContent || true
fi

# ---------- 2. hidden cases + reproduction probe -------------------------------
echo "== hidden cases =="
( cd "$SRC" && "$GIT" checkout -q -- hugolib/page_test.go )
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden case directories are present" >&2; reward=0
else
  echo "ok: $n_hidden hidden case directories"
fi

check_sha probe "$INTEGRITY_SHA_PROBE" "/app/probe_test.go" || reward=0
cp /app/probe_test.go "$SRC/hugolib/probe_test.go"
cp /tests/hidden/case-toml-section/capstan_hidden_toml_test.go "$SRC/hugolib/capstan_hidden_toml_test.go"
cp /tests/hidden/case-long-yaml-dated/capstan_hidden_yaml_test.go "$SRC/hugolib/capstan_hidden_yaml_test.go"
run_go "hidden cases and probe" /tmp/hidden.out \
  'TestCapstanQuayRawContentLeakProbe|TestCapstanQuayHiddenTomlSectionEmptyPage|TestCapstanQuayHiddenLongYamlDatedPage' \
  TestCapstanQuayRawContentLeakProbe \
  TestCapstanQuayHiddenTomlSectionEmptyPage \
  TestCapstanQuayHiddenLongYamlDatedPage || true

# ---------- 3. the project's own existing tests ---------------------------------
echo "== the project's own existing tests (regression slice) =="
run_go "existing page/front-matter tests" /tmp/existing.out \
  'TestPageWithDelimiter|TestPageWithCommentedOutFrontMatter|TestPageWithZeroFile|TestPagePaths|TestPageWithDateFields|TestPageSummary|TestPageWithMoreTag|TestPageManualSummary|TestPageWithDelimiterForMarkdownThatCrossesBorder|TestPageWithFrontMatterConfig|TestPageWithDate|TestFrontmatterPreserveDatatypesForSlices|TestPageDatesAllKinds|TestPageWithEmoji' \
  TestPageWithDelimiter \
  TestPageWithCommentedOutFrontMatter \
  TestPageWithZeroFile \
  TestPagePaths \
  TestPageWithDateFields \
  TestPageSummary \
  TestPageWithMoreTag \
  TestPageManualSummary \
  TestPageWithDelimiterForMarkdownThatCrossesBorder \
  TestPageWithFrontMatterConfig \
  TestPageWithDate \
  TestFrontmatterPreserveDatatypesForSlices \
  TestPageDatesAllKinds \
  TestPageWithEmoji || true

# ---------- cleanup --------------------------------------------------------------
rm -f "$SRC/hugolib/probe_test.go" \
      "$SRC/hugolib/capstan_hidden_toml_test.go" \
      "$SRC/hugolib/capstan_hidden_yaml_test.go"

echo "REWARD=$reward"
exit 0