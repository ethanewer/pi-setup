#!/bin/bash
# Verifier for ingot-flood: a task that repairs a 1997 C codebase so it
# builds on a 2024 toolchain and plays a recorded demo headlessly.
#
# For each build configuration (the project's stock flags, an -O2 set and an
# unoptimised set) we:
#   1. wipe and rebuild /app/src/linuxdoom-1.10 from scratch with that
#      configuration's flags (proving the delivered TREE is genuinely
#      repaired, whatever state the agent left the working directory in);
#   2. generate a fresh demo fixture (authored generator, no network);
#   3. run the freshly built binary headlessly under Xvfb;
#   4. require the game's own self-test line "timed <N> gametics in <M>
#      realtics" with the fixture's exact <N>.
#
# Reward is binary: every configuration and every fixture must pass.

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

SRC=/app/src/linuxdoom-1.10
BIN="$SRC/linux/linuxxdoom"
WORK=/tmp/ingot-work
rm -rf "$WORK"; mkdir -p "$WORK"

failures=""

# run_case LABEL [MAKE-CFLAGS-OVERRIDE...] WANT-GAMETICS DEMO-NAME GEN-SCRIPT
run_case () {
  label="$1"; shift
  want="$1"; shift
  demo="$1"; shift
  gen="$1"; shift
  # remaining args: make variable assignments, e.g. CFLAGS=...
  mkdir -p "$WORK/$label"
  cdir="$WORK/$label"

  echo "== case: $label (want timed $want gametics) =="
  if ! ( cd "$SRC" && rm -rf linux && mkdir -p linux \
         && make "$@" > "$cdir/build.log" 2>&1 ); then
    echo "   FAIL: rebuild with [$*] failed; tail of build log:"
    tail -6 "$cdir/build.log" | sed 's/^/     | /'
    failures="$failures|$label: rebuild failed"
    return
  fi
  [ -x "$BIN" ] || { failures="$failures|$label: no binary after rebuild"; return; }

  # The reward must be earned by the real engine, not a planted lookalike:
  # the deliverable binary has to be a genuine ELF executable...
  if [ "$(head -c4 "$BIN" 2>/dev/null)" != "$(printf '\x7fELF')" ]; then
    echo "   FAIL: $BIN is not an ELF executable (planted script or wrapper?)"
    failures="$failures|$label: binary is not an ELF executable"
    return
  fi
  # ...and the rebuild must actually have compiled the project's own sources
  # with the compiler (not just copied something into place).
  n_compiled=$(grep -cE -- '-c [A-Za-z0-9_]+[.]c -o linux/[A-Za-z0-9_]+[.]o' \
                     "$cdir/build.log" 2>/dev/null || true)
  if [ "${n_compiled:-0}" -lt 10 ]; then
    echo "   FAIL: build log has only ${n_compiled:-0} real gcc compile lines; the tree was not rebuilt"
    failures="$failures|$label: no genuine gcc compilation in build log"
    return
  fi

  # fresh fixture from the authored generator, exact gametic count
  cp "$gen" "$cdir/genwad.py" 2>/dev/null || ln -s "$gen" "$cdir/genwad.py"
  ( cd "$cdir" && python3 genwad.py "$cdir" "$want" "$demo" >/dev/null 2>&1 ) \
    || { failures="$failures|$label: fixture generation failed"; return; }

  ( cd "$cdir" && timeout 120 env DOOMWADDIR="$cdir" \
      xvfb-run -a -s "-screen 0 320x200x8" \
      "$BIN" -timedemo "$demo" -nodraw -noblit > "$cdir/run.log" 2>&1
  ) || true

  # The engine itself must boot: require its own init self-reports. These
  # lines are printed identically by every real run (all three flag sets:
  # stock, -O2, -O0) because they come before demo playback; a lookalike
  # never reaches them.
  for need in "W_Init: Init WADfiles" "R_Init: Init DOOM refresh daemon" \
              "P_Init: Init Playloop state"; do
    if ! grep -qF -- "$need" "$cdir/run.log"; then
      echo "   FAIL: engine boot line missing from run log: $need"
      failures="$failures|$label: missing engine boot line: $need"
      return
    fi
  done

  if ! grep -qE "timed +${want} +gametics in +[0-9]+ +realtics" "$cdir/run.log"; then
    echo "   FAIL: demo did not report 'timed $want gametics'; run log:"
    grep -iE "error|timed|wad|not found" "$cdir/run.log" | tail -4 | sed 's/^/     | /'
    failures="$failures|$label: missing timing line for $want gametics"
    return
  fi
  echo "   ok: '$(grep -E "timed" "$cdir/run.log" | tail -1 | tr -d '\r')'"
}

# ---- visible case: the project's own stock flags, 100-tic fixture ----
run_case visible 100 d1 /app/genwad.py

# ---- hidden cases: different compiler flag sets AND demo lengths ----
for d in /tests/hidden/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/case.env" ] || { failures="$failures|hidden case $d has no case.env"; continue; }
  unset CF TICS DEMO
  . "$d/case.env"   # provides CF (make CFLAGS string), TICS, DEMO
  run_case "hidden" "$TICS" "$DEMO" "$d/genwad.py" "CFLAGS=$CF"
done

if [ -n "$failures" ]; then
  echo
  echo "VERIFIER FAILURES:"
  echo "$failures" | tr '|' '\n' | sed '/^$/d' | sed 's/^/  - /'
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

echo
echo "ALL CASES PASSED: stock flags + optimized + unoptimized rebuilds, all fixtures exact."
echo 1 > /logs/verifier/reward.txt
exit 0