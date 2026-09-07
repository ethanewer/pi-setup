#!/usr/bin/env bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
cd "$(dirname "$0")"
mkdir -p /logs/verifier

# run_verify.py prints the verdict (1/0) on stdout and every reason on stderr.
# The old form piped stderr to /dev/null and echoed nothing, so a failure left an
# empty test-stdout.txt and the only evidence was reward.txt containing 0. A
# missing fixture and a wrong answer were indistinguishable, which is how this
# task's lost /app/sample_access.log went undiagnosed. Keep the verdict parsing
# exact but retain the diagnostics.
err=$(mktemp)
res=$(python3 /tests/run_verify.py 2>"$err" | tr -d '[:space:]')
rc=$?
cat "$err" >&2
rm -f "$err"
if [ "$rc" -ne 0 ]; then
  echo "run_verify.py exited $rc before printing a verdict" >&2
fi
case "${res:-}" in
  1) echo 1 > /logs/verifier/reward.txt ;;
  *) echo 0 > /logs/verifier/reward.txt ;;
esac
exit 0