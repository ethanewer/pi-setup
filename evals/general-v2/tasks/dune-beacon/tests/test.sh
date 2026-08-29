#!/usr/bin/env bash
# Verifier for dune-beacon.
#
# Executes every deliverable and checks, independently of how the agent wrote
# them:
#   1. /app/solve.py --live reconstructs each shipped instance and each fresh
#      hidden maze (compared against reference copies in /tests/ref).
#   2. /app/maps/{reef,island,channel}.out exist and equal the true maps.
#   3. /app/ending.txt equals the exact ending message of the adventure.
#   4. /app/state/beacon.db has a flushed player row (reached_ending=1) plus
#      gameplay event rows (proves normal-quit flush).
#   5. /app/layout.vim, sourced in a clean headless Vim, reproduces the
#      captured tab/window/buffer topology.
#   6. /app/macros.vim macro(s) reproduce target_lines.txt from source_lines.txt
#      and their combined length stays under the 150-keystroke budget.
set -uo pipefail
mkdir -p /logs/verifier
reward=0
WORK=/tmp/verify_dune_beacon
rm -rf "$WORK"; mkdir -p "$WORK"

python3 - "$WORK" <<'PY'
import json, os, re, sqlite3, subprocess, sys

work = sys.argv[1]
REF = "/tests/ref"
HID = "/tests/hidden"
ENDING = "THE BEACON IS WOKEN; the storm breaks and the last gate is calmed."
LAYOUT_EXPECTED = ("tabs=2\ntab1:wins=2:deck.vim,cargo.txt\n"
                   "tab2:wins=3:sail.vim,rudder.vim,galley.txt")
BUDGET = 150

ok = True
def fail(msg):
    global ok
    ok = False
    print("FAIL: " + msg)

def maze_of(path):
    with open(path) as fh:
        return fh.read()

# ---- 1. /app/solve.py present + live reconstruction ----------------------
if not os.path.exists("/app/solve.py"):
    fail("/app/solve.py missing")
else:
    # shipped instances, executed fresh via --live
    for name in ["reef", "island", "channel"]:
        ref = os.path.join(REF, "instances", name + ".txt")
        out = os.path.join(work, name + ".out")
        r = subprocess.run([sys.executable, "/app/solve.py", "--live", ref, out],
                           capture_output=True, text=True)
        if r.returncode != 0:
            fail("solve.py --live crashed on %s: %s" % (name, r.stderr[-300:]))
        elif not os.path.exists(out) or maze_of(out) != maze_of(ref):
            fail("solve.py --live map does not match for shipped %s" % name)
    # fresh hidden mazes (generalization)
    for hid in sorted(os.listdir(HID)):
        if not hid.endswith(".txt"):
            continue
        ref = os.path.join(HID, hid)
        out = os.path.join(work, "hid_" + hid + ".out")
        r = subprocess.run([sys.executable, "/app/solve.py", "--live", ref, out],
                           capture_output=True, text=True)
        if r.returncode != 0:
            fail("solve.py --live crashed on hidden %s" % hid)
        elif not os.path.exists(out) or maze_of(out) != maze_of(ref):
            fail("solve.py --live map mismatch on hidden %s" % hid)

# ---- 2. /app/maps deliverables -------------------------------------------
for (name, mp) in [("reef", "/app/maps/reef.out"),
                   ("island", "/app/maps/island.out"),
                   ("channel", "/app/maps/channel.out")]:
    ref = os.path.join(REF, "instances", name + ".txt")
    if not os.path.exists(mp):
        fail("/app/maps/%s.out missing" % name)
    elif maze_of(mp) != maze_of(ref):
        fail("/app/maps/%s.out does not match the true map" % name)

# ---- 3. ending.txt --------------------------------------------------------
if not os.path.exists("/app/ending.txt"):
    fail("/app/ending.txt missing")
else:
    got = open("/app/ending.txt").read().strip()
    if got != ENDING:
        fail("ending.txt got %r want %r" % (got, ENDING))

# ---- 4. database flushed on normal exit ----------------------------------
db = "/app/state/beacon.db"
if not os.path.exists(db):
    fail("/app/state/beacon.db missing (was the game quit normally?)")
else:
    try:
        con = sqlite3.connect(db)
        rows = con.execute("SELECT reached_ending FROM players").fetchall()
        ev = con.execute("SELECT COUNT(*) FROM events").fetchone()[0]
        con.close()
        if not rows or rows[0][0] != 1:
            fail("players row reached_ending != 1 (got %r)" % rows)
        if ev < 1:
            fail("no event rows flushed to the db")
    except Exception as e:
        fail("db read error: %s" % e)

# ---- 5. layout.vim topology ----------------------------------------------
if not os.path.exists("/app/layout.vim"):
    fail("/app/layout.vim missing")
else:
    check = os.path.join(work, "check.vim")
    with open(check, "w") as fh:
        fh.write("set noerrorbells\nsource /app/layout.vim\n")
        fh.write('let s:lines=["tabs=".tabpagenr("$")]\n')
        fh.write("for t in range(1, tabpagenr('$'))\n")
        fh.write('  exec "tabnext " . t\n')
        fh.write('  let nb=[]\n')
        fh.write("  for w in range(1, winnr('$'))\n")
        fh.write('    call add(nb, bufname(winbufnr(w)))\n')
        fh.write("  endfor\n")
        fh.write('  call add(s:lines, printf("tab%d:wins=%d:%s", t, winnr("$"), join(nb, ",")))\n')
        fh.write("endfor\n")
        fh.write('call writefile(s:lines, %r)\n' % os.path.join(work, "sig.txt"))
        fh.write("qa!\n")
    r = subprocess.run(["vim", "-Nu", "NONE", "-i", "NONE", "-n",
                        "--not-a-term", "-S", check],
                       capture_output=True, text=True)
    sig_path = os.path.join(work, "sig.txt")
    if r.returncode != 0 or not os.path.exists(sig_path):
        fail("vim could not run layout.vim")
    else:
        sig = open(sig_path).read().rstrip("\n")
        if sig != LAYOUT_EXPECTED:
            fail("layout signature mismatch:\ngot:\n%s\nwant:\n%s" % (sig, LAYOUT_EXPECTED))

# ---- 6. macros.vim: functional + keystroke budget ------------------------
if not os.path.exists("/app/macros.vim"):
    fail("/app/macros.vim missing")
else:
    # length of all macro registers (a-z) combined
    lenfile = os.path.join(work, "maclen.txt")
    applydir = os.path.join(work, "mapply")
    os.makedirs(applydir, exist_ok=True)
    src = os.path.join(applydir, "source_lines.txt")
    dst = os.path.join(applydir, "transformed.txt")
    import shutil
    shutil.copy(os.path.join(REF, "source_lines.txt"), src)
    r1 = subprocess.run(
        ["vim", "-Nu", "NONE", "-i", "NONE", "-n", "--not-a-term",
         "-c", "source /app/macros.vim",
         "-c", 'let s=0',
         "-c", "for ch in split('abcdefghijklmnopqrstuvwxyz','\\zs') | exec 'let s+=len(@'.ch.')' | endfor",
         "-c", 'call writefile([string(s)], "%s")' % lenfile,
         "-c", "qa!"], capture_output=True, text=True)
    total = None
    if os.path.exists(lenfile):
        total = int(open(lenfile).read().strip())
    r2 = subprocess.run(
        ["vim", "-Nu", "NONE", "-i", "NONE", "-n", "--not-a-term",
         "-c", "source /app/macros.vim",
         "-c", "edit " + src,
         "-c", "%global/^/normal @q",
         "-c", "write! " + dst,
         "-c", "qa!"], capture_output=True, text=True)
    if total is None:
        fail("could not measure macro length")
    elif total > BUDGET:
        fail("total macro length %d exceeds budget %d" % (total, BUDGET))
    if not os.path.exists(dst) or maze_of(dst) != maze_of(os.path.join(REF, "target_lines.txt")):
        fail("applying macros did not transform source_lines into target_lines")
    else:
        print("macros length=%s within budget=%d" % (total, BUDGET))

# ---- reward ---------------------------------------------------------------
print("OK" if ok else "NOT_OK")
sys.exit(0 if ok else 1)
PY

if [ "$?" -eq 0 ]; then
  reward=1
else
  reward=0
fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
