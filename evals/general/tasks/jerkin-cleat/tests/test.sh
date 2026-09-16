#!/usr/bin/env bash
# Verifier for jerkin-cleat: upstream-clone image pipeline task.
#
# Graded contract (see instruction.md):
#   /app/pipeline.c     the delivered C source
#   /app/image_pipeline the executable the agent built from it
# The verifier recompiles /app/pipeline.c with gcc so the bytes on disk are
# what is measured, and compares its outputs byte-for-byte against a reference
# pipeline built from the SAME pinned upstream headers in /app/src.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

fail() { echo "FAIL: $*" >&2; echo 0 > /logs/verifier/reward.txt; exit 0; }

# --- deliverables must exist ---
[ -s /app/pipeline.c ] && [ -f /app/pipeline.c ] || fail "deliverable /app/pipeline.c is missing or empty"
[ -x /app/image_pipeline ] || fail "deliverable /app/image_pipeline is missing or not executable"

# --- the source must be a real C program built on the upstream library ---
grep -q "STB_IMAGE_IMPLEMENTATION" /app/pipeline.c || fail "/app/pipeline.c does not compile in the upstream stb_image implementation"
grep -q "/app/src" /app/pipeline.c || fail "/app/pipeline.c does not reference the upstream tree in /app/src"
if grep -qE "(^|[^A-Za-z])system[ (]|popen[ (]|execl|fork[ (]" /app/pipeline.c; then
  fail "/app/pipeline.c must be self-contained C, not a shell wrapper"
fi

# --- compile the delivered source fresh, and the reference, from the same headers ---
gcc -O2 -o /tmp/agent_pipeline /app/pipeline.c -lm || fail "deliverable /app/pipeline.c does not compile with gcc"
gcc -O2 -o /tmp/ref_pipeline /tests/ref_pipeline.c -lm || fail "internal error: could not compile the reference pipeline"

problems=0
PROBLEM() { echo "PROBLEM: $*" >&2; problems=$((problems + 1)); }

# grade one input directory.  $1 = case dir (can be the visible workspace too)
grade() {
  local cdir="$1" cname
  cname=$(basename "$cdir")
  local outr="/tmp/out/$cname" refr="/tmp/ref/$cname" report="/tmp/out/$cname.report" log="/tmp/out/$cname.log"
  rm -rf "$outr" "$refr"
  mkdir -p /tmp/out /tmp/ref "$outr" "$refr"

  "$bin" "$cdir" "$outr" "$report" >"$log" 2>&1 || PROBLEM "$cname: pipeline exited with status $?"
  /tmp/ref_pipeline "$cdir" "$refr" >/tmp/ref.log 2>&1 || PROBLEM "$cname: reference crashed"

  local refouts
  refouts=$(cd "$refr" && echo *.png)
  if [ "$refouts" = "*.png" ]; then PROBLEM "$cname: reference produced no outputs at all"; fi

  local ok
  ok=0
  for f in "$cdir"/*; do
    [ -f "$f" ] || continue
    local base stem
    base=$(basename "$f")
    stem=${base%.*}
    if [ -e "$refr/$stem.png" ]; then
      # decodable: output must exist and be byte-identical to the reference
      ok=$((ok + 1))
      if [ ! -e "$outr/$stem.png" ]; then
        PROBLEM "$cname: missing output for $base"
      elif ! cmp -s "$refr/$stem.png" "$outr/$stem.png"; then
        PROBLEM "$cname: byte mismatch on output for $base"
      fi
      grep -qE "^OK $base([ ]|$)" "$log" || PROBLEM "$cname: no OK line for $base on stdout"
    else
      # undecodable for the reference library: must be a recorded FAIL whose
      # reason is the library's OWN explanation (stbi_failure_reason) verbatim,
      # must produce no output, and must appear on stdout with the same reason.
      # The reference library's reason for each name is taken from ref.log
      # ("REF SKIP <name>: <reason>").  Failure reasons are deterministic
      # literals in the shared headers, verified stable across compilations.
      local rreason areason sreason
      rreason=$(awk -v n="REF SKIP $base: " 'index($0, n) == 1 { print substr($0, length(n) + 1); exit }' /tmp/ref.log)
      areason=$(awk -v n="FAIL $base " 'index($0, n) == 1 { print substr($0, length(n) + 1); exit }' "$report")
      sreason=$(awk -v n="FAIL $base " 'index($0, n) == 1 { print substr($0, length(n) + 1); exit }' "$log")
      if [ -z "$rreason" ]; then
        PROBLEM "$cname: reference recorded no failure reason for $base"
      elif [ "$areason" != "$rreason" ]; then
        PROBLEM "$cname: report reason for $base is not the library's own reason"
      elif [ "$sreason" != "$rreason" ]; then
        PROBLEM "$cname: stdout reason for $base is not the library's own reason"
      fi
      [ -e "$outr/$stem.png" ] && PROBLEM "$cname: FAIL input $base nevertheless produced an output image"
    fi
  done
  [ "$ok" -eq 0 ] && PROBLEM "$cname: no decodable inputs were found"

  # the report must contain exactly the failures: one line per undecodable input
  local bad
  bad=$(grep -c "^FAIL " "$report" || true)
  local expect
  expect=$(find "$cdir" -maxdepth 1 -type f | wc -l)
  local got
  got=$(cd "$refr" && echo *.png | tr ' ' '\n' | grep -v '^\*$' | wc -l)
  if [ "$bad" != "$((expect - got))" ]; then
    PROBLEM "$cname: report has $bad FAIL lines but $((expect - got)) inputs were undecodable"
  fi
}

# --- run the graded executable deliverable on the visible workspace ---
bin=/app/image_pipeline
grade /app/fixtures

# --- run the recompiled deliverable source on the hidden cases ---
bin=/tmp/agent_pipeline
for c in /tests/hidden/case*/; do
  [ -d "$c" ] || continue
  grade "$c"
done

if [ "$problems" -eq 0 ]; then
  echo "verdict: PASS"
  echo 1 > /logs/verifier/reward.txt
else
  echo "verdict: FAIL ($problems problems)"
  echo 0 > /logs/verifier/reward.txt
fi
exit 0