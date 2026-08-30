#!/bin/bash
# Real oracle for basalt-fathom: write the solve.py program, then RUN
# solve-evidence to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"

cat > "$SOLVER" <<'PY'
import hashlib
import json
import sys


def attest(P: bytes) -> str:
    h1 = hashlib.md5(P).digest()
    h2 = hashlib.sha512(h1[:8]).digest()
    h3 = hashlib.blake2b(h2[:24] + h1[6:14], digest_size=20).digest()
    return hashlib.sha3_256(h3 + P).hexdigest()


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: solve.py attest <file> | solve-evidence", file=sys.stderr)
        sys.exit(2)
    if args[0] == "attest" and len(args) == 2:
        with open(args[1], "rb") as fh:
            print(attest(fh.read()))
        return
    if args[0] == "solve-evidence":
        attestations = {}
        with open("/app/artifacts/manifest.txt", encoding="utf-8") as fh:
            names = [ln.strip() for ln in fh if ln.strip()]
        for name in names:
            with open("/app/artifacts/" + name, "rb") as fh:
                attestations[name] = attest(fh.read())
        with open("/app/answer.json", "w", encoding="utf-8") as fh:
            json.dump(
                {"attestations": attestations, "artifact_count": len(names)},
                fh, indent=2,
            )
        return
    print("unknown command", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" solve-evidence

echo "solve.sh done -> $SOLVER and /app/answer.json"
ls -l "$SOLVER" /app/answer.json
