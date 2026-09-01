#!/bin/bash
# Oracle for vesper-broker: author /app/gadget.py (the real deliverable), run
# it on the visible mission to mint /app/dispatch.msg, then deliver the
# message through the real consumer to produce /app/escape-proof.
# Never reads /tests.
set -eu

GADGET="/app/gadget.py"

# ---- 1. Write the deliverable authoring script (this IS the work).
cat > "$GADGET" <<'PY'
import os
import pickle
import sys


class Escape:
    """Pickle gadget: executing this reduction runs the escape command."""

    def __init__(self, command):
        self.command = command

    def __reduce__(self):
        return (os.system, (self.command,))


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: gadget.py <mission_file> <output_msg>")
    mission_path, out_path = sys.argv[1], sys.argv[2]

    token = ""
    with open(mission_path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            token = line.strip()
            if token:
                break
    if not token:
        sys.exit("gadget.py: mission file has no token")
    if not all(c.isalnum() or c == "-" for c in token):
        sys.exit("gadget.py: unsupported token characters")

    command = "printf 'escaped=%s\\n' > /app/escape-proof" % token
    with open(out_path, "wb") as fh:
        pickle.dump(Escape(command), fh)


if __name__ == "__main__":
    main()
PY
chmod +x "$GADGET"

# ---- 2. Mint the visible message and deliver it through the real consumer.
python3 "$GADGET" /app/mission.txt /app/dispatch.msg
rm -f /app/escape-proof
python3 /app/dispatch.py /app/dispatch.msg

echo "solve.sh done -> $GADGET, /app/dispatch.msg, /app/escape-proof"
cat /app/escape-proof
ls -l "$GADGET" /app/dispatch.msg /app/escape-proof
