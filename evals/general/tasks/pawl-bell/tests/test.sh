#!/bin/bash
# Verifier for pawl-bell (upstream-clone chess-engine task on
# official-stockfish/Stockfish).
#
# Requirements, in order:
#   1. Provenance: the engine binary exists at the clone's build output path
#      and the checkout at /app/src is the pinned upstream repository.
#   2. The engine is real: the verifier drives /app/src/src/stockfish itself
#      over a UCI session (handshake, per-depth info lines, score, bestmove)
#      for one hidden position at depth 7 and the transcript must carry the
#      deterministic expected values.
#   3. The /app/uci_play.py deliverable runs correctly on all three hidden
#      positions at depth 7, printing exactly `bestmove:<move> score:<cp>`.
#
# Reward is binary and written on every exit path (the trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import glob
import os
import re
import select
import subprocess
import sys
import time

DEPTH = 7
BIN = "/app/src/src/stockfish"
DRV = "/app/uci_play.py"
PINNED_SHA = "59aae690f91d6f69aac194f447d84b4a2c3be778"
UPSTREAM_URL = "https://github.com/official-stockfish/Stockfish.git"

# Expected deterministic depth-7 results for the three hidden positions,
# precomputed from this pinned commit (identical across 3 runs and across
# x86-64 / x86-64-sse41-popcnt builds; node counts equal too).
EXPECTED = {
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1": ("e2e4", 24),
    "3k4/8/8/8/8/8/5P2/4K3 w - - 0 1": ("e1e2", 419),
    "r1b1kbnr/ppppqppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1": ("b1c3", 108),
}

# Additional raw-engine probe positions, precomputed from this pinned commit.
# These are NOT among the hidden cases; they exist so a stub that only knows
# the three hidden answers cannot impersonate the engine (a real build answers
# any position correctly).
EXTRA_ENGINE = {
    "7k/8/8/8/8/8/8/R3K3 w - - 0 1": ("a1a3", 487),
    "2r2k2/8/8/8/8/8/8/2R2K2 w - - 0 1": ("c1c8", 473),
}

failures = []
def fail(msg):
    failures.append(msg)


# --- 1) provenance -----------------------------------------------------------
if not os.path.exists(BIN):
    fail(f"engine binary missing: {BIN} (build the checkout with its Makefile)")
elif not os.access(BIN, os.X_OK):
    fail(f"engine binary not executable: {BIN}")
else:
    # must be inside a git checkout of the pinned upstream project
    if not os.path.isdir("/app/src/.git"):
        fail("/app/src is not a git checkout (engine must come from the clone)")
    else:
        r = subprocess.run(
            ["git", "-C", "/app/src", "remote", "get-url", "origin"],
            capture_output=True, text=True,
        )
        origin = (r.stdout or "").strip()
        if origin not in (UPSTREAM_URL, UPSTREAM_URL.removesuffix(".git"),
                          "https://github.com/official-stockfish/Stockfish"):
            fail(f"clone origin is not {UPSTREAM_URL}: {origin!r}")

if not os.path.exists(DRV):
    fail(f"driver deliverable missing: {DRV}")
elif not os.access(DRV, os.X_OK):
    fail(f"driver deliverable not executable: {DRV}")

# --- 2) drive the engine binary directly over UCI ----------------------------
def drive_raw(binary, fen, depth, budget=90):
    """Run a full UCI session against `binary`; return a dict of transcript facts."""
    proc = subprocess.Popen(
        [binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    buf = b""
    deadline = time.time() + budget
    state = "handshake"
    result = {"id_name": None, "uciok": False, "readyok": False,
              "info_depths": {}, "best": None, "score": None}

    def send(cmd):
        proc.stdin.write((cmd + "\n").encode())
        proc.stdin.flush()

    send("uci")
    try:
        while time.time() < deadline:
            r, _, _ = select.select([proc.stdout], [], [], 1.0)
            if not r:
                continue
            chunk = os.read(proc.stdout.fileno(), 65536)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                line = raw.decode("utf-8", "replace").rstrip("\r")
                if line.startswith("id name "):
                    result["id_name"] = line
                elif line == "uciok":
                    result["uciok"] = True
                    send("isready")
                elif line == "readyok" and state == "handshake":
                    result["readyok"] = True
                    state = "search"
                    send(f"position fen {fen}")
                    send(f"go depth {depth}")
                elif line.startswith("bestmove"):
                    parts = line.split()
                    if len(parts) > 1:
                        result["best"] = parts[1]
                        send("quit")
                        # keep reading briefly so 'quit' is consumed; bestmove
                        # terminates the search, we have what we need
                        state = "done"
                    if state == "done":
                        try:
                            proc.stdin.close()
                        except Exception:
                            pass
                        return result
                m = re.match(r"^info depth (\d+) .*? score cp (-?\d+)", line)
                if m:
                    d = int(m.group(1))
                    result["info_depths"][d] = ("cp", int(m.group(2)))
                m = re.match(r"^info depth (\d+) .*? score mate (-?\d+)", line)
                if m:
                    d = int(m.group(1))
                    result["info_depths"][d] = ("mate", int(m.group(2)))
    except Exception as exc:  # noqa: BLE001 - verifier must not die silently
        fail(f"engine session crashed: {exc!r}")
    finally:
        try:
            proc.stdin.close()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
    if time.time() >= deadline:
        fail("engine did not answer in time (possible hang)")
    return result

startpos = next(iter(EXPECTED))
exp_move, exp_score = EXPECTED[startpos]
facts = drive_raw(BIN, startpos, DEPTH)
if facts["uciok"]:
    if not facts["id_name"] or "Stockfish" not in facts["id_name"]:
        fail(f"uci 'id name' line does not identify Stockfish: {facts['id_name']!r}")
    if not facts["readyok"]:
        fail("engine never answered 'readyok' to isready")
    if facts["best"] != exp_move:
        fail(f"raw-engine bestmove for hidden position 1 at depth {DEPTH}: "
             f"got {facts['best']!r}, expected {exp_move!r}")
    got = facts["info_depths"].get(DEPTH)
    if got != ("cp", exp_score):
        fail(f"raw-engine score for hidden position 1 at depth {DEPTH}: "
             f"got {got!r}, expected ('cp', {exp_score})")
    missing = [d for d in range(1, DEPTH + 1) if d not in facts["info_depths"]]
    if missing:
        fail(f"transcript structure: no info line at depth(s) {missing}")

# --- 2b) the engine must be real: probe it on positions it was never given ---
    for fen, (exp_move, exp_score) in EXTRA_ENGINE.items():
        f2 = drive_raw(BIN, fen, DEPTH)
        if not f2["uciok"]:
            fail(f"extra probe position did not handshake: {fen!r}")
            continue
        if f2["best"] != exp_move:
            fail(f"extra probe position {fen!r}: bestmove got {f2['best']!r}, "
                 f"expected {exp_move!r}")
        got = f2["info_depths"].get(DEPTH)
        if got != ("cp", exp_score):
            fail(f"extra probe position {fen!r}: depth-{DEPTH} score got {got!r}, "
                 f"expected ('cp', {exp_score})")
        missing = [d for d in range(1, DEPTH + 1) if d not in f2["info_depths"]]
        if missing:
            fail(f"extra probe position {fen!r}: no info line at depth(s) {missing}")
else:
    # failure already reported above or by id/ready checks; if the session
    # died before uciok, the details are in the previous checks.
    if not failures:
        fail("engine never said 'uciok'")

# --- 3) the driver deliverable against every hidden case ---------------------
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    cases = sorted(os.listdir(hidden))
else:
    cases = []
if len(cases) < 2:
    fail(f"expected at least two hidden cases, found {len(cases)}")

for case in cases:
    fen_path = os.path.join(hidden, case, "fen.txt")
    if not os.path.isfile(fen_path):
        fail(f"hidden case {case}: missing fen.txt")
        continue
    fen = open(fen_path, encoding="utf-8").read().strip()
    if fen not in EXPECTED:
        fail(f"hidden case {case}: unknown fixture FEN {fen!r}")
        continue
    exp_move, exp_score = EXPECTED[fen]
    try:
        r = subprocess.run(
            ["timeout", "120", sys.executable, DRV, fen, str(DEPTH)],
            capture_output=True, text=True, timeout=130,
        )
    except subprocess.TimeoutExpired:
        fail(f"driver run on case {case} timed out")
        continue
    got_line = (r.stdout or "").strip()
    want_line = f"bestmove:{exp_move} score:{exp_score}"
    if r.returncode != 0:
        tail = (r.stderr or "").strip()[-800:]
        fail(f"driver on case {case} exited {r.returncode}; stderr: {tail}")
    elif got_line != want_line:
        fail(f"driver on case {case}: printed {got_line!r}; expected {want_line!r}")

# --- reward ------------------------------------------------------------------
if failures:
    print("PAWL-BELL VERIFIER FAILURES:")
    for f in failures:
        print(" - " + f)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0\n")
    print("reward: 0")
    sys.exit(0)

print("pawl-bell verifier: all checks passed")
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1\n")
print("reward: 1")
sys.exit(0)
PY