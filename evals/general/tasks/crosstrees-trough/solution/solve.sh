#!/bin/bash
# Oracle for crosstrees-trough. Localises and repairs the real upstream defect
# in the tmux tree at /app/src, writes the required /app/repro.sh deliverable,
# rebuilds, and proves both with the project's own regression test for this
# drawing path. Reads only /app/src (never /tests).
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
test -f screen-write.c || { echo "oracle: not the tmux tree" >&2; exit 1; }

# ---- 1. deliverable: /app/repro.sh -----------------------------------------
# A self-contained reproduction: right-hand pane of a horizontal split (pane
# xoff = 10), variation-selector-always-wide on, pencil U+270F + VS16 written
# on the second line of the pane. While the defect is present the glyph cell is
# dropped (rendered as a space); with the defect fixed the line round-trips.
cat > /app/repro.sh <<'REPRO'
#!/bin/sh
# Reproduction for: variation-selector-widened characters are dropped in a
# pane whose horizontal offset is nonzero (right side of a horizontal split).
# Exits non-zero with a message while the defect is present, 0 once fixed.
BIN=${1:-/app/src/tmux}
[ -x "$BIN" ] || { echo "no tmux binary at $BIN" >&2; exit 2; }
PATH=/bin:/usr/bin
TERM=screen
LC_ALL=C.UTF-8
export TERM LC_ALL
TMUX="$BIN -Lrepro$$ -f/dev/null"
TMP=$(mktemp)
trap "rm -f $TMP; $TMUX kill-server 2>/dev/null" 0 1 15
$TMUX kill-server 2>/dev/null
$TMUX new -d -x20 -y6 -s test || exit 1
$TMUX set -g status off || exit 1
$TMUX set -s variation-selector-always-wide on || exit 1
WINDOW=$($TMUX neww -dPF '#{window_id}' "exec sleep 100") || exit 1
PANE=$($TMUX splitw -dhPF '#{pane_id}' -t "$WINDOW" "exec sleep 100") || exit 1
$TMUX selectw -t "$WINDOW" || exit 1
$TMUX respawnp -k -t "$PANE" \
    "printf '\nA\342\234\217\357\270\217B'; exec sleep 100" || exit 1
sleep 1
$TMUX capturep -p -t "$PANE" >$TMP || exit 1
want=$(printf 'A\342\234\217\357\270\217B')
got=$(sed -n 2p $TMP)
if [ "$got" = "$want" ]; then
    echo "repro: OK, glyph present ('$got')"
    exit 0
fi
echo "repro: FAIL, widened character dropped ('$got' instead of '$want')" >&2
exit 1
REPRO
chmod +x /app/repro.sh

# ---- 2. the fix: include the pane horizontal offset in the visibility check --
# In screen_write_combine, the visibility window for a combined (widened)
# character is queried with pane-relative column cx, but window_visible_ranges
# expects window coordinates: with wp->xoff != 0 the queried range lies outside
# the pane (typically over the neighbour pane to the left), the character is
# judged obscured and replaced by a space. Adding wp->xoff fixes the coordinate
# mismatch. This is the exact upstream fix (696a16cc) for GitHub issue 5511.
python3 - <<'PY'
path = "screen-write.c"
src = open(path).read()

a1 = "\tu_int\t\t\t i, n, cx = s->cx, cy = s->cy, vis, yoff = 0;\n"
b1 = "\tu_int\t\t\t i, n, cx = s->cx, cy = s->cy, vis;\n"
a2 = "\tint\t\t\t force_wide = 0, zero_width = 0;\n"
b2 = "\tint\t\t\t force_wide = 0, zero_width = 0;\n\tint\t\t\t xoff = 0, yoff = 0;\n"
a3 = ("\tif (wp != NULL)\n\t\tyoff = wp->yoff;\n"
      "\tr = window_visible_ranges(wp, cx - n, cy + yoff, n, NULL);\n")
b3 = ("\tif (wp != NULL) {\n\t\txoff = wp->xoff;\n\t\tyoff = wp->yoff;\n\t}\n"
      "\tr = window_visible_ranges(wp, xoff + cx - n, cy + yoff, n, NULL);\n")

for old, new in ((a1, b1), (a2, b2), (a3, b3)):
    if src.count(old) != 1:
        raise SystemExit("oracle: expected buggy text not found (count=%d)"
                         % src.count(old))
    src = src.replace(old, new)
open(path, "w").write(src)
print("oracle: visibility check now uses window coordinates (xoff + cx - n)")
PY

# ---- 3. rebuild --------------------------------------------------------------
make -j1 >/tmp/oracle_make.log 2>&1 || { echo "oracle: rebuild failed" >&2; tail -5 /tmp/oracle_make.log >&2; exit 1; }

# ---- 4. prove: deliverable and the project's own regression both pass -------
sh /app/repro.sh || { echo "oracle: repro still fails after fix" >&2; exit 1; }
(cd /app/src/regress && TEST_TMUX=$PWD/../tmux sh ./tty-draw-line.sh) \
    || { echo "oracle: upstream tty-draw-line.sh fails after fix" >&2; exit 1; }
echo "oracle: fix in place, /app/repro.sh and regress/tty-draw-line.sh pass"
exit 0