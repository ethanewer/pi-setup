#!/usr/bin/env bash
# End-to-end smoke test of the installed setup, one print-mode run per capability.
#
#   tests/smoke.sh            everything
#   tests/smoke.sh --quick    skip the browser and workflow runs (the slow ones)
#
# Run after ./install.sh whenever Pi, agent-browser, or a fork changes. Costs a few
# cents in model calls. Exits non-zero if any check fails.
set -uo pipefail

QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf 'export const GREETING = "hello-from-alpha";\n' > "$WORK/alpha.ts"

PASS=0; FAIL=0
run_with() { # run_with <entrypoint> <label> <expected-substring> <prompt>
  local entrypoint="$1" label="$2" expect="$3" prompt="$4" out
  printf '  ... %s\n' "$label"
  out="$(cd "$WORK" && "$entrypoint" -p "$prompt" 2>&1)"
  if grep -qF -- "$expect" <<< "$out"; then
    PASS=$((PASS + 1)); printf '  PASS  %s\n' "$label"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL  %s\n         expected %q in:\n%s\n' "$label" "$expect" "$(sed 's/^/           /' <<< "$out" | tail -8)"
  fi
}
run() { run_with pi "$@"; }

printf '\nVersions\n'
printf '  pi             %s\n' "$(pi --version 2>&1 | tail -1)"
printf '  p              %s\n' "$(p --version 2>&1 | tail -1)"
printf '  agent-browser  %s\n' "$(agent-browser --version 2>&1 | tail -1)"

printf '\nChecks\n'
# Every extension's tools must be registered. A fork that failed to load is silently
# absent from this list rather than raising an error at startup.
run "tools registered" "monitor_kill_all" \
  "List the names of every tool you have available, comma separated, nothing else."
run "built-in bash" "SMOKE-BASH-OK" \
  "Run the bash command 'echo SMOKE-BASH-OK' and reply with nothing else."
run "btw side conversation" "hello-from-alpha" \
  "/btw What constant does alpha.ts export? Reply with only its value."
run_with p "lean p btw side conversation" "hello-from-alpha" \
  "/btw What constant does alpha.ts export? Reply with only its value."

if [[ "$QUICK" == "0" ]]; then
  run "agent_browser" "Example Domain" \
    "Use agent_browser to open https://example.com and reply with only the page title."
  run "dynamic workflow" "GAMMA-DELTA" \
    "Run a dynamic workflow with a single agent whose only job is to return the exact string GAMMA-DELTA, then reply with only what it returned."
else
  printf '  skip  agent_browser and dynamic workflow (--quick)\n'
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" == "0" ]]
