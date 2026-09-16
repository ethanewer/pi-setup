#!/usr/bin/env python3
"""UCI driver for the Stockfish engine (task pawl-bell).

Usage: python3 /app/uci_play.py "<FEN>" <depth>

Prints exactly one line on stdout on success:
    bestmove:<move> score:<cp>
or, when the final info line at the requested depth reports a mate score:
    bestmove:<move> score:mate<M>
Exits nonzero with a diagnostic on stderr on any failure.
"""

import re
import subprocess
import sys

ENGINE = "/app/src/src/stockfish"


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} \"<FEN>\" <depth>", file=sys.stderr)
        return 2
    fen = sys.argv[1]
    try:
        depth = int(sys.argv[2])
    except ValueError:
        print(f"invalid depth: {sys.argv[2]!r}", file=sys.stderr)
        return 2

    try:
        proc = subprocess.Popen(
            [ENGINE],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
    except OSError as exc:
        print(f"cannot start engine {ENGINE}: {exc}", file=sys.stderr)
        return 1

    def send(cmd: str) -> None:
        proc.stdin.write(cmd + "\n")
        proc.stdin.flush()

    try:
        send("uci")
        handshake = False
        for line in proc.stdout:
            if line.startswith("uciok"):
                handshake = True
                break
        if not handshake:
            print("engine did not complete the uci handshake", file=sys.stderr)
            return 1

        send("isready")
        for line in proc.stdout:
            if line.startswith("readyok"):
                break

        send(f"position fen {fen}")
        send(f"go depth {depth}")

        best = None
        score = None
        cp_re = re.compile(r"^info depth (\d+) .*? score cp (-?\d+)")
        mate_re = re.compile(r"^info depth (\d+) .*? score mate (-?\d+)")
        for line in proc.stdout:
            m = cp_re.match(line)
            if m and int(m.group(1)) == depth:
                score = int(m.group(2))
            m = mate_re.match(line)
            if m and int(m.group(1)) == depth:
                score = "mate" + m.group(2)
            if line.startswith("bestmove"):
                parts = line.split()
                if len(parts) > 1:
                    best = parts[1]
                break

        if best is None or score is None:
            print(
                f"engine returned no bestmove/score for depth {depth}",
                file=sys.stderr,
            )
            return 1

        print(f"bestmove:{best} score:{score}")
        return 0
    finally:
        try:
            proc.stdin.write("quit\n")
            proc.stdin.flush()
        except Exception:
            pass
        try:
            proc.stdin.close()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())