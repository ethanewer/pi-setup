#!/bin/bash
# Real oracle for kestrel-vault: write the general driver solve.py, then RUN it
# on the shipped scenario to produce /app/ending.txt and /app/state/vault.db
# via a real clean quit. Never reads /tests.
set -eu

SOLVER="/app/solve.py"

cat > "$SOLVER" <<'PY'
import subprocess
import sys


def read_line(proc):
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError("game closed stdout unexpectedly")
    return line.rstrip("\n")


def main():
    game_py, scenario, ending_out, db_path = sys.argv[1:5]
    proc = subprocess.Popen(
        [sys.executable, game_py, scenario, "--db", db_path],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        text=True, bufsize=1,
    )
    try:
        banner = read_line(proc)
        if not banner.startswith("VAULT-READY"):
            raise RuntimeError("no banner: %r" % banner)

        proc.stdin.write("look\n")
        proc.stdin.flush()
        line = read_line(proc)
        if not line.startswith("CONTAINERS "):
            raise RuntimeError("bad look response: %r" % line)
        names = [n.strip() for n in line[len("CONTAINERS "):].split(",") if n.strip()]

        gems = []
        for name in names:
            proc.stdin.write("search %s\n" % name)
            proc.stdin.flush()
            resp = read_line(proc)
            if resp.startswith("FOUND "):
                gems.append(resp[len("FOUND "):].strip())

        for gem in gems:
            proc.stdin.write("take %s\n" % gem)
            proc.stdin.flush()
            read_line(proc)

        for gem in gems:
            proc.stdin.write("place %s\n" % gem)
            proc.stdin.flush()
            read_line(proc)

        proc.stdin.write("seal\n")
        proc.stdin.flush()
        line = read_line(proc)
        if not line.startswith("SEALED "):
            raise RuntimeError("seal failed: %r" % line)
        ending = line[len("SEALED "):]

        proc.stdin.write("quit\n")
        proc.stdin.flush()
        bye = read_line(proc)
        if bye != "BYE":
            raise RuntimeError("expected BYE, got %r" % bye)
    finally:
        try:
            proc.stdin.close()
        except Exception:
            pass
    rc = proc.wait(timeout=60)
    if rc != 0:
        raise RuntimeError("game did not exit cleanly (rc=%d)" % rc)

    with open(ending_out, "w", encoding="utf-8") as fh:
        fh.write(ending)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/vault.py /app/scenario.json /app/ending.txt /app/state/vault.db

echo "solve.sh done -> $SOLVER /app/ending.txt /app/state/vault.db"
ls -l "$SOLVER" /app/ending.txt /app/state/vault.db
cat /app/ending.txt
