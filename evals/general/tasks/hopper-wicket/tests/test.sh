#!/usr/bin/env bash
# Verifier for hopper-wicket (release pipeline).
#
# Executes the deliverable /app/release.py against three hidden commit-graph
# fixtures and checks: the derived version, byte-exact changelog, annotated
# release tag at HEAD, provenance fields, the recorded artifact hash against
# an independent rebuild of the HEAD tree, and the exit-3 "nothing to
# release" edge case on a re-run.
set -u
mkdir -p /logs/verifier
reward=0
work=$(mktemp -d)
trap 'rm -rf "$work"; [ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
fail(){ echo "FAIL: $*" >&2; FAILED=1; }

FAILED=0

for case in H1 H2 H3; do
  mkdir -p "$work/$case"
  if ! tar -xzf "/tests/hidden/$case/repo.tar.gz" -C "$work/$case"; then
    fail "$case: cannot extract repo.tar.gz"
    continue
  fi
  repo="$work/$case/repo"
  exp=$(cat "/tests/hidden/$case/expected_version.txt" 2>/dev/null) || { fail "$case: cannot read expected version"; continue; }
  out="$work/$case/out"

  # --- run the deliverable ------------------------------------------------
  if ! python3 /app/release.py "$repo" "$out" >"$work/$case/run.log" 2>&1; then
    fail "$case: release.py exited non-zero"
    sed 's/^/    /' "$work/$case/run.log" >&2
    continue
  fi

  # --- 1) version --------------------------------------------------------
  if [ -f "$out/version.txt" ]; then
    got=$(cat "$out/version.txt")
    if [ "$got" != "$exp" ]; then
      fail "$case: version.txt is '$got', expected '$exp'"
    fi
  else
    fail "$case: no version.txt written"
    continue
  fi

  # -----------------------------------------------------------------------
  # 2) changelog bytes (structure AND content must match exactly)
  if [ -f "$out/CHANGELOG.md" ]; then
    if ! cmp -s "$out/CHANGELOG.md" "/tests/hidden/$case/expected_changelog.md"; then
      fail "$case: CHANGELOG.md differs from expected"
      diff -u "/tests/hidden/$case/expected_changelog.md" "$out/CHANGELOG.md" \
        | head -40 | sed 's/^/    /' || true
    fi
  else
    fail "$case: no CHANGELOG.md written"
  fi

  # -----------------------------------------------------------------------
  # 3) tag exists, is annotated, points at HEAD
  head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)
  tagrev=$(git -C "$repo" rev-parse --verify --quiet "refs/tags/v$exp^{}" 2>/dev/null || true)
  if [ -z "$tagrev" ]; then
    fail "$case: tag v$exp is missing"
  else
    if [ -n "$head" ] && [ "$tagrev" != "$head" ]; then
      fail "$case: tag v$exp does not point at HEAD"
    fi
    if [ "$(git -C "$repo" cat-file -t "v$exp" 2>/dev/null || true)" != "tag" ]; then
      fail "$case: tag v$exp is not annotated"
    fi
  fi

  # -----------------------------------------------------------------------
  # 4) artifact + provenance + verifier-side rebuild
  art="$out/release-$exp.tar.gz"
  if [ ! -f "$art" ]; then
    fail "$case: artifact release-$exp.tar.gz missing"
    continue
  fi
  pv="$out/provenance.txt"
  if [ ! -f "$pv" ]; then
    fail "$case: provenance.txt missing"
    continue
  fi
  vline=$(grep '^version: ' "$pv" 2>/dev/null || true)
  tline=$(grep '^tag: ' "$pv" 2>/dev/null || true)
  aline=$(grep '^artifact: ' "$pv" 2>/dev/null || true)
  cline=$(grep '^commit: ' "$pv" 2>/dev/null || true)
  hline=$(grep '^artifact_sha256: ' "$pv" 2>/dev/null || true)
  [ "$vline" = "version: $exp" ] || { fail "$case: provenance 'version:' line is '$vline'"; }
  [ "$tline" = "tag: v$exp" ] || { fail "$case: provenance 'tag:' line is '$tline'"; }
  [ "$aline" = "artifact: release-$exp.tar.gz" ] || { fail "$case: provenance 'artifact:' line is '$aline'"; }
  [ "$cline" = "commit: $head" ] || { fail "$case: provenance 'commit:' line is '$cline'"; }
  recorded=${hline#"artifact_sha256: "}
  case "$recorded" in
    [0-9a-f][0-9a-f]*)
      # 64 hex chars, lowercase
      if [ "${#recorded}" -ne 64 ]; then
        fail "$case: provenance hash has wrong length"
      fi
      ;;
    *)
      fail "$case: provenance hash line malformed: '$hline'"
      ;;
  esac

  rebuilt="$work/$case/rebuild.tar.gz"
  if git -C "$repo" archive --format=tar HEAD | gzip -n > "$rebuilt" 2>/dev/null; then
    rh=$(sha256sum "$rebuilt" 2>/dev/null | cut -d' ' -f1)
    ah=$(sha256sum "$art" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$rh" ] && [ "$rh" != "$recorded" ]; then
      fail "$case: recorded artifact_sha256 does not match an independent rebuild"
    fi
    if [ -n "$ah" ] && [ "$ah" != "$recorded" ]; then
      fail "$case: shipped artifact bytes do not match the recorded hash"
    fi
  else
    fail "$case: verifier rebuild pipeline failed"
  fi
done

# ---------------------------------------------------------------------------
# edge: a repository whose latest release tag is at HEAD has nothing to
# release; the tool must say so and create nothing.
repo="$work/H1/repo"
out2="$work/H1/out2"
rc=0
python3 /app/release.py "$repo" "$out2" >"$work/H1/run2.log" 2>&1 || rc=$?
if [ "$rc" -ne 3 ]; then
  fail "re-run on an already-released repo must exit 3, got rc=$rc"
fi
grep -q 'no releasable commits' "$work/H1/run2.log" 2>/dev/null \
  || fail "re-run did not report 'no releasable commits'"
if [ -d "$out2" ] && [ -n "$(ls -A "$out2" 2>/dev/null)" ]; then
  fail "re-run with nothing to release still wrote outputs"
fi

# ---------------------------------------------------------------------------
if [ "$FAILED" = 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0