#!/bin/bash
# Verifier for sennit-foresheet: a real-upstream debugging task on
# tmux/tmux (GitHub issue #5576).
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# malformed session-relative +N/-N window and pane offsets (+0, +foo, -0,
# ...) are silently accepted and applied to the fallback item instead of
# being rejected with "can't find window: ..." / "can't find pane: ...".
# The parent tree is 73db0a54... (the project's own test-first commit: the
# regression checks are already committed and FAILING there); the fix is the
# merge d44bfda2... that upstream applied to cmd-find.c (whose tree at the
# dev-line commit 00f3899a... is not Linux-buildable). The agent must also
# deliver /app/repro.sh, its own failing reproduction.
#
# The verifier:
#   0. asserts toolchain/harness integrity (sha256 of git, /bin/sh and the
#      two golden regression scripts bound to constants recorded from the
#      built image);
#   1. asserts tree provenance: HEAD is still the pinned parent, the fix
#      commits are unreachable from the working clone, exactly one commit,
#      no assume-unchanged/skip-worktree index flags, the only modified
#      tracked files are cmd-find.c (with at least one modification), no
#      tracked file deleted, no other tracked change;
#   2. force-rebuilds the agent's tree (rm built binary, make -j1) so the
#      binary under test is provably built from the agent's sources;
#   3. runs the project's own regression tests for this bug (golden copies
#      extracted from the fix tree at image build time into /opt/golden):
#      regress/targets.sh and regress/targets-panes.sh, which FAIL on the
#      pristine parent tree and must PASS on a fixed tree;
#   4. runs two authored hidden cases that drive the same code path with
#      inputs the upstream tests do not use (overlong numeric offsets that
#      overflow strtonum; malformed pane offsets on a non-current window),
#      plus a loop of randomized malformed offsets generated at run time;
#   5. runs a slice of the project's own existing suite (window-ops,
#      session-ops, options-values, run-shell-output) from the golden
#      copies, proving the fix broke nothing else;
#   6. runs the agent's own /app/repro.sh twice: against a pristine rebuild
#      of the parent tree (fresh `git worktree` + build in /tmp) where it
#      MUST FAIL, and against the fixed build (copied to a neutral path)
#      where it MUST PASS -- proving the delivered reproduction really does
#      distinguish the bug from the fix.
#
# Reward is binary and written on every exit path (re)unconditionally, so no
# stale or pre-forged /logs/verifier/reward.txt can survive.
#
# Hardening notes (bypasses demonstrated and closed):
#   - pre-write /logs/verifier/reward.txt then crash: closed by rm + trap
#     that writes ${reward:-0} unconditionally;
#   - swap /usr/bin/git so the provenance checks always pass: closed by the
#     recorded sha256 (and all git calls go through $GIT);
#   - swap /bin/sh so every regress/hidden/repro run exits 0 trivially:
#     closed by the recorded sha256, AND the randomized probes in section 4
#     invoke the binary directly from bash as a redundant semantic check;
#   - edit the tree's regress scripts to delete the checks: closed by using
#     the /opt/golden copies, which the agent is not supposed to touch and
#     which are hash-bound;
#   - replace /app/src/tmux with a fake: closed by rm + make in section 2
#     (the Makefile is tracked, so a tampered build system fails 1);
#   - swap a stale-but-fixed object file: cmd-find.o (and Makefile, and all
#     other build products) are UNTRACKED, so provenance cannot see them; a
#     container whose cmd-find.c still contains the bug but whose cmd-find.o
#     was compiled from a fixed copy would relink into a "fixed" binary and
#     pass every behavioural gate. Demonstrated in review (reward 1 with the
#     buggy tracked source). Closed: section 2 now re-runs ./autogen.sh +
#     ./configure (regenerating the generated Makefile/configurables from the
#     tracked Makefile.am/configure.ac exactly as the image build did) and
#     then make clean + make -j1, so every object is provably recompiled from
#     the current tracked sources; no prebuilt object or hand-edited Makefile
#     can survive into the binary.
#   - fix only the exact inputs of targets.sh (git-grep +0/+foo/-0/-foo):
#     closed by the hidden cases and the randomized numeric probes.
#
# Re-record INTEGRITY_* (sha256sum inside the built image) only if the base
# image's git/sh or the golden files genuinely change.

trap 'printf "%s\n" "${reward:-0}" > /logs/verifier/reward.txt' EXIT
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt
reward=1

SRC=/app/src
PARENT_SHA=73db0a54e5ae5abf80bb790829222c9760f60b1d
FIX_SHA=d44bfda26d2468b5f474087b56f93eda34c541b6
FIX_SHA_DEV=00f3899aea035666fa9e7bd60bc7c2cf36c8e745
GOLDEN=/opt/golden/regress

GIT=/usr/bin/git
SH=/bin/sh
BIN="$SRC/tmux"

# sha256 recorded from the built sennit-foresheet image at authoring time.
INTEGRITY_SHA_GIT=2a8c18fbf43da9f692d75474c72bea9dfd796c260b0f3dfe456376abc3bbd668
INTEGRITY_SHA_SH=86d31f6fb799e91fa21bad341484564510ca287703a16e9e46c53338776f4f42
INTEGRITY_SHA_GOLDEN_TARGETS=ec3acd53877b645abf848a849fd6dd6b97a7d79142fc599e96e4c56d9a0a1f34
INTEGRITY_SHA_GOLDEN_PANES=be45c059315ae2c52a515944a177ee1ab933d31d76b95573ba902ae08394eaa6

fail ()
{
	echo "FAIL: $*" >&2
	reward=0
}

ok ()
{
	echo "ok: $*"
}

# ---------------- 0. toolchain and harness integrity ------------------------
echo "== toolchain and harness integrity =="
check_sha () # check_sha LABEL EXPECTED FILE
{
	label="$1"; expected="$2"; file="$3"
	if [ ! -f "$file" ]; then
		fail "integrity/$label: $file is missing (toolchain or harness was replaced or deleted)"
		return 1
	fi
	actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
	if [ "$actual" != "$expected" ]; then
		fail "integrity/$label: $file does not match the recorded bytes (was it replaced?) expected $expected actual ${actual:-<unreadable>}"
		return 1
	fi
	ok "integrity/$label: matches the recorded bytes"
}
check_sha git    "$INTEGRITY_SHA_GIT"            "$GIT"    || true
check_sha sh     "$INTEGRITY_SHA_SH"             "$SH"     || true
check_sha golden "$INTEGRITY_SHA_GOLDEN_TARGETS" "$GOLDEN/targets.sh" || true
check_sha golden "$INTEGRITY_SHA_GOLDEN_PANES"   "$GOLDEN/targets-panes.sh" || true

# ---------------- 1. tree provenance -----------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
	fail "/app/src is not a git clone"
elif [ "$("$GIT" -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
	fail "/app/src HEAD is not the pinned parent commit"
else
	ok "HEAD is $PARENT_SHA"
fi

if "$GIT" -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
	fail "the master fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
	ok "master fix commit $FIX_SHA not present in the working clone"
fi
if "$GIT" -C "$SRC" cat-file -e "${FIX_SHA_DEV}^{commit}" 2>/dev/null; then
	fail "the dev-line fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
	ok "dev-line fix commit $FIX_SHA_DEV not present in the working clone"
fi

ncommits=$("$GIT" -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
	fail "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit"
else
	ok "exactly one commit object reachable in the working clone"
fi

flagged=$("$GIT" -C "$SRC" ls-files -v 2>/dev/null | awk 'NF >= 2 && $1 ~ /^[hS]/ { print }')
if [ -n "$flagged" ]; then
	fail "tracked files carry assume-unchanged/skip-worktree index flags (changes would be hidden from status):"
	# shellcheck disable=SC2001
	echo "$flagged" | sed 's/^/    | /' >&2
else
	ok "no assume-unchanged / skip-worktree flags in the index"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
	[ -z "$line" ] && continue
	rest="${line#?? }"
	case "$line" in
		" M cmd-find.c")
			saw_mod=1
			;;
		" M "*)
			if [ "$rest" = "cmd-find.c" ]; then
				saw_mod=1
			else
				fail "a tracked file other than cmd-find.c was modified: $line"
				bad_tree=1
			fi
			;;
		" D "*)
			fail "a tracked file was deleted: $line"
			bad_tree=1
			;;
		"?? "*)
			# untracked files are allowed (the agent may add its own sources)
			:
			;;
		*)
			fail "unexpected working-tree change: $line"
			bad_tree=1
			;;
	esac
done <<< "$("$GIT" -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then :; else ok "no disallowed working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
	fail "no modification under cmd-find.c (the deliverable /app/src is unchanged; no fix implemented)"
else
	ok "at least one modification under cmd-find.c"
fi

# ---------------- 2. force-rebuild the agent's tree --------------------------
# The rebuild must prove the binary came from the agent's real sources:
#   ./autogen.sh && ./configure  regenerate the (untracked, generated)
#       Makefile and configurables from the TRACKED Makefile.am/configure.ac,
#       so a hand-edited generated Makefile cannot smuggle foreign objects in;
#   make clean                   discards every already-built object, so a
#       stale-but-fixed .o (cmd-find.o is untracked and invisible to the
#       provenance gate) cannot survive the relink;
#   make -j1                     recompiles everything from the current
#       sources, including the one tracked file the task may change.
echo "== rebuild the agent's sources (autogen+configure+clean, provably from the current sources) =="
rm -f "$BIN"
if ( cd "$SRC" \
    && ./autogen.sh > /tmp/regen.log 2>&1 \
    && ./configure >> /tmp/regen.log 2>&1 \
    && make clean >> /tmp/rebuild.log 2>&1 \
    && make -j1 >> /tmp/rebuild.log 2>&1 ); then
	out=$("$BIN" -V 2>&1)
	if [ "$out" = "tmux next-3.8" ]; then
		ok "clean rebuild succeeded and $BIN -V prints '$out'"
	else
		fail "rebuilt binary reports unexpected version: '$out'"
	fi
else
	fail "clean rebuild of /app/src failed:"
	echo "--- autogen/configure log ---" >&2
	tail -8 /tmp/regen.log | sed 's/^/    | /' >&2
	echo "--- build log tail ---" >&2
	tail -20 /tmp/rebuild.log | sed 's/^/    | /' >&2
fi

# ---------------- 3. golden tests (project's own regression tests) -----------
echo "== golden tests (upstream regression tests for this bug) =="
if [ ! -x "$BIN" ]; then
	fail "no built binary at $BIN; cannot run the golden tests"
else
	if ( cd "$GOLDEN" && TEST_TMUX="$BIN" "$SH" ./targets.sh > /tmp/golden-targets.out 2>&1 ); then
		ok "regress/targets.sh passes against the rebuilt binary"
	else
		fail "regress/targets.sh fails against the rebuilt binary"
		cat /tmp/golden-targets.out | sed 's/^/    | /' >&2
	fi
	if ( cd "$GOLDEN" && TEST_TMUX="$BIN" "$SH" ./targets-panes.sh > /tmp/golden-panes.out 2>&1 ); then
		ok "regress/targets-panes.sh passes against the rebuilt binary"
	else
		fail "regress/targets-panes.sh fails against the rebuilt binary"
		cat /tmp/golden-panes.out | sed 's/^/    | /' >&2
	fi
fi

# ---------------- 4a. authored hidden cases ----------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
	[ -d "$case" ] || continue
	n_hidden=$((n_hidden + 1))
done
if [ "$n_hidden" -lt 2 ]; then
	fail "fewer than two hidden case directories exist under /tests/hidden"
else
	ok "$n_hidden hidden case directories"
fi

run_hidden () # run_hidden CASE_FILE
{
	file="$1"
	if [ ! -f "$file" ]; then
		fail "hidden case file missing: $file"
		return 1
	fi
	if TMUX="$BIN" "$SH" "$file" > /tmp/hidden.out 2>&1; then
		ok "hidden case $(basename "$file") passes"
		return 0
	fi
	fail "hidden case $(basename "$file") fails against the rebuilt binary"
	cat /tmp/hidden.out | sed 's/^/    | /' >&2
	return 1
}
run_hidden /tests/hidden/case-overflow-window/case-overflow-window.sh || true
run_hidden /tests/hidden/case-pane-nonzero-window/case-pane-nonzero-window.sh || true

# ---------------- 4b. randomized malformed offsets ---------------------------
# Runtime-generated overflow numbers: static reading of /tests (or of the
# golden scripts) cannot pre-special-case every input, so a fix that merely
# special-cases the known malformed literals cannot pass this section. The
# probes invoke the binary directly from bash (not via /bin/sh).
echo "== randomized malformed-offset probes =="
"$BIN" -L"sennit-rnd$$" -f/dev/null new -d -x80 -y24 -s alpha >/dev/null 2>&1
"$BIN" -L"sennit-rnd$$" new-window -t alpha >/dev/null 2>&1
"$BIN" -L"sennit-rnd$$" new-window -t alpha >/dev/null 2>&1
"$BIN" -L"sennit-rnd$$" split-window -h -t alpha:1 >/dev/null 2>&1
rnd_probes=0
for i in 1 2 3; do
	big=$(( 10000000000 + $RANDOM * 100000 + $RANDOM ))   # 11-16 decimal digits
	big="$big$RANDOM"
	# need strictly > INT_MAX (9-10 digits); assemble a 20+ digit number:
	big="9$big$big"
	out=$("$BIN" -L"sennit-rnd$$" has-session -t "alpha:+$big" 2>&1)
	rc=$?
	if [ $rc -ne 1 ] || [ "$out" != "can't find window: +$big" ]; then
		fail "randomized probe: '+$big' was not rejected (rc=$rc out='$out')"
		rnd_probes=$((rnd_probes + 1))
	fi
	out=$("$BIN" -L"sennit-rnd$$" has-session -t "alpha:1.+$big" 2>&1)
	rc=$?
	if [ $rc -ne 1 ] || [ "$out" != "can't find pane: +$big" ]; then
		fail "randomized probe: 'alpha:1.+$big' was not rejected (rc=$rc out='$out')"
		rnd_probes=$((rnd_probes + 1))
	fi
done
"$BIN" -L"sennit-rnd$$" kill-server >/dev/null 2>&1
if [ "$rnd_probes" = 0 ]; then ok "all 6 randomized malformed-offset probes rejected"; fi

# ---------------- 5. project's own suite slice -------------------------------
echo "== the project's own suite (regression slice) =="
for s in window-ops.sh session-ops.sh options-values.sh run-shell-output.sh; do
	if ( cd "$GOLDEN" && TEST_TMUX="$BIN" "$SH" ./"$s" > /tmp/slice.out 2>&1 ); then
		ok "regress/$s passes"
	else
		fail "regress/$s fails against the rebuilt binary"
		tail -10 /tmp/slice.out | sed 's/^/    | /' >&2
	fi
done

# ---------------- 6. the agent's own reproduction ----------------------------
echo "== agent's reproduction (/app/repro.sh) =="
REPRO=/app/repro.sh
if [ ! -f "$REPRO" ]; then
	fail "/app/repro.sh is missing"
elif [ ! -x "$REPRO" ]; then
	fail "/app/repro.sh exists but is not executable"
else
	ok "/app/repro.sh exists and is executable"
	# Pre-fix direction: rebuild the pristine parent tree in a throwaway
	# git worktree (no network, all caches warm) and require the repro to
	# FAIL against that binary.
	WT=$(mktemp -d /tmp/sennit-pristine.XXXXXX) || WT=
	if [ -n "$WT" ] && "$GIT" -C "$SRC" worktree add --detach "$WT" HEAD > /tmp/wtadd.out 2>&1; then
		if ( cd "$WT" && ./autogen.sh > /dev/null 2>&1 \
		    && ./configure > /dev/null 2>&1 \
		    && make -j1 > /dev/null 2>&1 ); then
			ok "pristine parent tree rebuilt in a throwaway worktree"
			if TMUX="$WT/tmux" "$SH" "$REPRO" > /tmp/repro-pre.out 2>&1; then
				fail "/app/repro.sh PASSED against the pristine (buggy) build - it does not reproduce the bug"
			else
				ok "/app/repro.sh fails against the pristine buggy build"
			fi
		else
			fail "pristine worktree build failed; cannot run the pre-fix repro check"
			tail -5 /tmp/wtadd.out | sed 's/^/    | /' >&2
		fi
		"$GIT" -C "$SRC" worktree remove --force "$WT" > /dev/null 2>&1
		rm -rf "$WT"
	else
		fail "could not create the pristine worktree (git worktree add failed)"
		[ -n "$WT" ] && rm -rf "$WT"
	fi

	# Post-fix direction: a copy of the fixed binary at a neutral path, so
	# the script cannot key on a familiar path; only behavior distinguishes.
	FC=$(mktemp -d /tmp/sennit-fixed.XXXXXX) || FC=
	if [ -n "$FC" ] && cp "$BIN" "$FC/tmux" 2>/dev/null; then
		if TMUX="$FC/tmux" "$SH" "$REPRO" > /tmp/repro-post.out 2>&1; then
			ok "/app/repro.sh passes against the fixed build"
		else
			fail "/app/repro.sh FAILS against the fixed build:"
			cat /tmp/repro-post.out | sed 's/^/    | /' >&2
		fi
		rm -rf "$FC"
	else
		fail "could not copy the fixed binary for the post-fix repro check"
	fi
fi

# ---------------- done --------------------------------------------------------
echo "REWARD=$reward"
exit 0