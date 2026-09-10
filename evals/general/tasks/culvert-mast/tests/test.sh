#!/bin/bash
# Verifier for tasks/culvert-mast (executes-deliverable).
#  1) runs the shipped binary /app/culvert on the visible fixture and checks
#     byte-exact json + table output and exit codes;
#  2) REBUILDS /app/culvert-src/main.go offline with the documented single
#     command (this enforces the stdlib-only constraint: any third-party
#     dependency makes the rebuild fail), then
#  3) runs the rebuilt binary across four hidden config/env/flag combinations,
#     asserting byte-exact output and exact exit codes (0/1/2/3 paths).
# Writes exactly 1 or 0 to /logs/verifier/reward.txt.
# Guarantee a reward on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

H=/tests/hidden
BIN=/app/culvert
SRC=/app/culvert-src/main.go
OUT=/tmp/culvert-out
RC=/tmp/culvert-rc
FAIL=false
failadd() { echo "FAIL: $1" >&2; FAIL=true; }

# run [VAR=val ...] -- command args...
# executes with a scrubbed environment (PATH/HOME plus any VAR=val prefix),
# capturing stdout in $OUT and the exit code in $RC.
run() {
  local args=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do args+=("$1"); shift; done
  if [ "$1" = "--" ]; then shift; fi
  env -i PATH="$PATH" HOME=/tmp "${args[@]}" "$@" >"$OUT" 2>/tmp/culvert-err.log
  echo $? >"$RC"
}
wrc()     { [ "$(cat "$RC")" = "$1" ] || failadd "$2: exit $(cat "$RC") want $1"; }
wbytes()  { cmp -s "$OUT" "$1" || failadd "$2: stdout differs from $(basename "$1")"; }
wempty()  { [ ! -s "$OUT" ] || failadd "$2: stdout not empty ($(wc -c <"$OUT") bytes)"; }
# wstderr TEXT LABEL: the pinned diagnostic template must appear on stderr
wstderr() { grep -Fq -- "$1" /tmp/culvert-err.log || failadd "$2: stderr missing '$1' (stderr: $(head -c 120 /tmp/culvert-err.log 2>/dev/null | tr '\n' '|'))"; }

# ---------------------------------------------------------------------------
# 0) deliverables exist
# ---------------------------------------------------------------------------
if [ ! -x "$BIN" ]; then failadd "deliverable $BIN missing or not executable"; fi
if [ ! -f "$SRC" ]; then failadd "deliverable $SRC missing"; fi

# ---------------------------------------------------------------------------
# 1) offline rebuild of the delivered source (stdlib-only enforcement)
# ---------------------------------------------------------------------------
RB=""
if [ -f "$SRC" ]; then
  mkdir -p /tmp/gocache /tmp/rebuild
  rm -f /tmp/rebuild/culvert
  if GOCACHE=/tmp/gocache HOME=/tmp go build -o /tmp/rebuild/culvert "$SRC" \
      >/tmp/rebuild.log 2>&1; then
    RB=/tmp/rebuild/culvert
  else
    failadd "source rebuild from $SRC failed (offline, stdlib-only)"
    cat /tmp/rebuild.log >&2
  fi
fi

# ---------------------------------------------------------------------------
# 2) visible fixture (shipped binary, default config /app/culvert.conf)
# ---------------------------------------------------------------------------
run -- "$BIN" resolve --format json
wrc 0 "visible resolve json rc"
wbytes /tests/expected_resolve.json "visible resolve json"

run -- "$BIN" resolve --format table
wrc 0 "visible resolve table rc"
wbytes /tests/expected_resolve_table.txt "visible resolve table"

run -- "$BIN" diff --format json
wrc 0 "visible diff json rc"
wbytes /tests/expected_diff.json "visible diff json"

run -- "$BIN" check --format table
wrc 0 "visible check table rc"
wbytes /tests/expected_check_table.txt "visible check table"

# ---------------------------------------------------------------------------
# 3) hidden cases (rebuilt binary)
# ---------------------------------------------------------------------------
if [ -n "$RB" ]; then
  # H1: config + env + flag all override different settings
  run CULVERT_REGION=eu-west CULVERT_MAX_BATCH=999 -- "$RB" resolve \
      --config "$H/H1/culvert.conf" --retries=1 --format json
  wrc 0 "H1 resolve json rc"
  wbytes "$H/H1/expected_resolve.json" "H1 resolve json"

  run CULVERT_REGION=eu-west CULVERT_MAX_BATCH=999 -- "$RB" diff \
      --config "$H/H1/culvert.conf" --retries=1 --format json
  wrc 1 "H1 diff json rc"
  wbytes "$H/H1/expected_diff.json" "H1 diff json"

  run CULVERT_REGION=eu-west CULVERT_MAX_BATCH=999 -- "$RB" diff \
      --config "$H/H1/culvert.conf" --retries=1 --format table
  wrc 1 "H1 diff table rc"
  wbytes "$H/H1/expected_diff_table.txt" "H1 diff table"

  # H2: unparseable env value -> usage error, empty stdout; check reports it
  run CULVERT_TIMEOUT_MS=abc -- "$RB" resolve --config "$H/H2/culvert.conf" --format json
  wrc 2 "H2 resolve invalid env rc"
  wempty "H2 resolve invalid env stdout"
  wstderr "culvert: timeout_ms (env): not an integer" "H2 resolve invalid env stderr"

  run CULVERT_TIMEOUT_MS=abc -- "$RB" check --config "$H/H2/culvert.conf" --format json
  wrc 1 "H2 check json rc"
  wbytes "$H/H2/expected_check.json" "H2 check json"

  # H2b: a flag value the stdlib parser rejects is also exit 2, still nothing on stdout
  run -- "$RB" resolve --config "$H/H2/culvert.conf" --retries=abc --format json
  wrc 2 "H2 flag value rejected by stdlib flag parser"
  wempty "H2b flag value rejected stdout"

  # H3: invalid values in all three layers; check reports each once
  run CULVERT_VERBOSE=yes CULVERT_REGION= -- "$RB" check \
      --config "$H/H3/culvert.conf" --max-batch=0 --format json
  wrc 1 "H3 check json rc"
  wbytes "$H/H3/expected_check.json" "H3 check json"

  run CULVERT_VERBOSE=yes CULVERT_REGION= -- "$RB" resolve \
      --config "$H/H3/culvert.conf" --max-batch=0 --format json
  wrc 2 "H3 resolve invalid config endpoint rc"
  wempty "H3 resolve invalid config endpoint stdout"
  wstderr "culvert: endpoint (config): must start with http:// or https://" "H3 resolve invalid config endpoint stderr"

  # H4: malformed config file -> exit 3, nothing on stdout, for both subcommands
  run -- "$RB" resolve --config "$H/H4/culvert.conf" --format json
  wrc 3 "H4 resolve malformed config rc"
  wempty "H4 resolve malformed config stdout"
  wstderr "culvert: config error: line 2" "H4 resolve malformed config stderr"

  run -- "$RB" check --config "$H/H4/culvert.conf" --format table
  wrc 3 "H4 check malformed config rc"
  wempty "H4 check malformed config stdout"
else
  failadd "hidden cases skipped: delivered source did not rebuild"
fi

# ---------------------------------------------------------------------------
# finish
# ---------------------------------------------------------------------------
if [ "$FAIL" = true ]; then
  echo "0" > /logs/verifier/reward.txt
else
  echo "1" > /logs/verifier/reward.txt
fi
echo "REWARD=$(cat /logs/verifier/reward.txt)"
exit 0